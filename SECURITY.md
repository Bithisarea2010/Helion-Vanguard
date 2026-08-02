# Security Policy

## Supported version

Security fixes are applied to the latest published Helion Vanguard release and
the current `main` branch.

| Version | Supported |
|:--|:--:|
| 1.2.x | ✅ |
| Earlier versions | ❌ |

## Report a vulnerability privately

Please **do not open a public issue** for a suspected vulnerability, leaked
credential, unsafe download, or security-sensitive exploit.

Use GitHub's private reporting form instead:

**[Report a vulnerability privately](https://github.com/Bithisarea2010/Helion-Vanguard/security/advisories/new)**

Include the affected version, macOS version, reproduction steps, expected and
observed behavior, and any proof-of-concept material that is safe to share.
Reports will be acknowledged as soon as practical. Please allow time to verify,
fix and publish an updated build before disclosing the issue publicly.

## Release integrity

Official builds are published only through this repository's
[GitHub Releases](https://github.com/Bithisarea2010/Helion-Vanguard/releases).
Each release should include a SHA-256 digest. Compare it locally with:

```sh
shasum -a 256 Helion-Vanguard-macOS-v1.2.1.zip
```

The current macOS build is ad-hoc signed and is not Apple-notarized. That status
is documented openly in [`docs/BUILD.md`](docs/BUILD.md#code-signing-status).
Never download Helion Vanguard from an unlisted mirror claiming to provide an
"official" build.

## Repository protections

The default branch requires pull requests, blocks force pushes and deletion,
requires resolved review conversations, and enforces a linear history. GitHub
secret scanning, push protection and Dependabot security updates are enabled.
