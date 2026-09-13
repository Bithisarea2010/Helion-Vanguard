"""Summarize bounded capture-free wall-clock runs; not an aggregate frame p95."""
from pathlib import Path
import json, re, statistics
ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'docs/evidence/quality-2026-09-13'
paths = [EVIDENCE / 'before/measured-combat.log'] + sorted((EVIDENCE / 'after').glob('perf-*.log'))
rows = []
for path in paths:
    text = path.read_text()
    samples = []
    for line in text.splitlines():
        if '[BENCH] t=' not in line:
            continue
        row = {key: float(value) for key, value in re.findall(r'(\w+)=([0-9.]+)', line)}
        if row['t'] >= 3.0:
            samples.append(row)
    if not samples:
        continue
    rows.append({
        'log': str(path.relative_to(ROOT)), 'samples_after_first_3s': len(samples),
        'median_bucket_fps': round(statistics.median(x['fps'] for x in samples), 2),
        'bucket_fps_range': [min(x['fps'] for x in samples), max(x['fps'] for x in samples)],
        'median_bucket_p95_ms': round(statistics.median(x['p95'] for x in samples), 2),
        'worst_frame_ms': max(x['worst'] for x in samples),
        'max_reported_video_memory_mb': max(x['vram'] for x in samples),
        'median_draw_calls': statistics.median(x['drawcalls'] for x in samples),
        'median_primitives': statistics.median(x['prims'] for x in samples),
        'completed': '[BENCH] harness complete' in text,
        'engine_errors': len(re.findall(r'^(?:SCRIPT )?ERROR:', text, re.MULTILINE)),
        'warnings': len(re.findall(r'^WARNING:', text, re.MULTILINE)),
    })
result = {'method': 'Median of one-second wall-clock buckets after the first 3 mission seconds. Bucket p95 is not a whole-run percentile. No screenshots during measurement.', 'runs': rows}
(EVIDENCE / 'after/performance-summary.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result, indent=2))
