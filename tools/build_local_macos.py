#!/usr/bin/env python3
"""Package the installed, tested Godot runtime and an exported game PCK.

This local Apple Silicon build does not require downloads, developer accounts,
or mismatched 4.7 templates. It never overwrites a previous build implicitly.
Run: python3 tools/build_local_macos.py [--engine /path/to/Godot]
"""
from pathlib import Path
import argparse, hashlib, json, plistlib, shutil, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--engine', default='/Applications/További programok Boldi/Fejlesztés/Godot.app/Contents/MacOS/Godot')
parser.add_argument("--replace", action="store_true", help="Replace only this tool's previously generated 1.3.0 local build after a successful new export")
args = parser.parse_args()
engine = Path(args.engine).resolve()
destination = ROOT / 'build/quality-1.3.0'
if destination.exists():
    manifest_path = destination / 'build-manifest.json'
    previous = json.loads(manifest_path.read_text()) if manifest_path.is_file() else {}
    if not args.replace or previous.get('game_version') != '1.3.0' or previous.get('runtime_source') != str(engine):
        raise SystemExit(f'Refusing to overwrite unrecognized or unapproved build: {destination}')
destination.parent.mkdir(exist_ok=True)
staging = Path(tempfile.mkdtemp(prefix='helion-build-')) # sign outside Desktop metadata indexing

def run(argv):
    subprocess.run([str(x) for x in argv], cwd=ROOT, check=True)

try:
    app = staging / 'Helion Vanguard.app'
    macos = app / 'Contents/MacOS'
    resources = app / 'Contents/Resources'
    macos.mkdir(parents=True)
    resources.mkdir(parents=True)
    pack = resources / 'HelionVanguard.pck'
    run([engine, '--headless', '--path', ROOT, '--export-pack', 'macOS', pack])
    if not pack.exists() or pack.stat().st_size < 1000000:
        raise RuntimeError('Export did not produce a usable resource pack')
    executable = macos / 'HelionVanguard'
    # A thin copy of the installed official universal executable preserves the
    # exact engine revision tested in the editor, and saves ~170 MB per build.
    run(['/usr/bin/lipo', engine, '-thin', 'arm64', '-output', executable])
    executable.chmod(0o755)
    shutil.copyfile(ROOT / 'assets/icons/icon.icns', resources / 'icon.icns')
    info = {
        'CFBundleDevelopmentRegion': 'en', 'CFBundleExecutable': 'HelionVanguard',
        'CFBundleIdentifier': 'com.originalgames.helionvanguard',
        'CFBundleInfoDictionaryVersion': '6.0', 'CFBundleName': 'Helion Vanguard',
        'CFBundlePackageType': 'APPL', 'CFBundleIconFile': 'icon.icns',
        'CFBundleShortVersionString': '1.3.0', 'CFBundleVersion': '1.3.0',
        'LSApplicationCategoryType': 'public.app-category.games',
        'LSMinimumSystemVersion': '13.0', 'NSHighResolutionCapable': True,
        'NSSupportsAutomaticGraphicsSwitching': True,
    }
    with (app / 'Contents/Info.plist').open('wb') as f:
        plistlib.dump(info, f)
    (app / 'Contents/PkgInfo').write_bytes(b'APPL????')
    notices = staging / 'Licenses'
    notices.mkdir()
    for name in ['LICENSE', 'LICENSES.md']:
        shutil.copy2(ROOT / name, notices / name)
    # Extract the actual compiled engine's full MIT / third-party notices.
    helper = staging / 'extract_notices.gd'
    notices_path = str(notices).replace('\\', '\\\\').replace('"', '\\"')
    helper.write_text('extends SceneTree\nfunc _initialize():\n _extract.call_deferred()\nfunc _extract():\n'
        f' var file = FileAccess.open("{notices_path}/Godot.txt", FileAccess.WRITE)\n'
        ' file.store_string(Engine.get_license_text() + "\\n\\n" + JSON.stringify(Engine.get_license_info(), "  "))\n'
        ' file.close()\n var game = root.get_node_or_null("Game")\n if game:\n  game.prepare_shutdown()\n await create_timer(0.2).timeout\n quit()\n')
    run([engine, '--headless', '--path', ROOT, '--script', helper, '--', '--defaults'])
    helper.unlink()
    run(['/usr/bin/xattr', '-cr', app]) # only this freshly generated bundle
    run(['/usr/bin/codesign', '--force', '--deep', '--sign', '-', app])
    run(['/usr/bin/xattr', '-cr', app])
    run(['/usr/bin/codesign', '--verify', '--deep', '--strict', app])
    version = subprocess.check_output([engine, '--version'], text=True).strip()
    manifest = {
        'game_version': '1.3.0', 'engine': version, 'architecture': 'arm64',
        'runtime_source': str(engine), 'runtime_sha256': hashlib.sha256(engine.read_bytes()).hexdigest(),
        'pack_sha256': hashlib.sha256(pack.read_bytes()).hexdigest(),
        'signing': 'local ad-hoc; strict verified in staging; no account or notarization',
        'desktop_metadata': 'FileProvider may attach FinderInfo to the app after copying; original signing verification is performed before that metadata is added',
        'packaging': 'installed Godot editor runtime plus exported resource pack; no editor data or MCP autoload',
    }
    (staging / 'build-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (staging / 'RUN.txt').write_text('Open Helion Vanguard.app. Apple Silicon, macOS 13+.\n'
        'This is a local ad-hoc signed build, not a notarized public release.\n'
        'W/S thrust/brake; mouse steer; LMB guns; RMB missiles; R target; Shift boost; Esc pause.\n'
        'Hangar contains all eight unlocked ships, including Peregrine and Aegis.\n')
    if destination.exists():
        shutil.rmtree(destination) # recognized build; replacement has now passed export/signing
    shutil.move(str(staging), str(destination))
    print(f'BUILD_READY {destination}', flush=True)
except BaseException:
    # Only this invocation's unique staging directory is removed on failure.
    shutil.rmtree(staging)
    raise
