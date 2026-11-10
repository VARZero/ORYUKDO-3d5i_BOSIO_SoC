"""고정한 Linux 원본과 패치로 실보드에 사용한 소스 트리를 복원한다."""
import argparse, hashlib, json, subprocess, tarfile, urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
meta = json.loads((root/'software/linux/source_manifest.json').read_text())
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--archive', type=Path, default=root/'artifacts/linux-6.12.tar.xz')
p.add_argument('--output', type=Path, required=True, help='새 소스 디렉터리의 상위 경로')
a = p.parse_args()
target = a.output.resolve()/'linux-6.12'
if target.exists(): raise SystemExit(f'기존 소스를 덮어쓰지 않습니다: {target}')
if not a.archive.exists():
    a.archive.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(meta['upstream_url'], a.archive)
if hashlib.sha256(a.archive.read_bytes()).hexdigest() != meta['upstream_sha256']:
    raise SystemExit('Linux 원본 SHA256 불일치')
a.output.mkdir(parents=True, exist_ok=True)
with tarfile.open(a.archive) as tf:
    tf.extractall(a.output, filter='data')
patch = root/'software/linux/patches/0001-clocksource-trace-v2.patch'
subprocess.run(['patch','--batch','--fuzz=0','-p1','-i',str(patch)],cwd=target,check=True)
for item in meta['changes']:
    if hashlib.sha256((target/item['path']).read_bytes()).hexdigest() != item['sha256']:
        raise SystemExit('패치 결과 SHA256 불일치: '+item['path'])
print('PASS Linux 6.12 trace-v2 소스 복원:', target)
