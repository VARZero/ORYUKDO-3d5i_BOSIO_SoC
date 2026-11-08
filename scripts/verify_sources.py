"""실보드에 사용한 RTL 및 패키지의 변경 여부를 확인한다."""
from pathlib import Path
import hashlib, json
root=Path(__file__).resolve().parents[1]
def check(rel, expected):
    p=root/rel
    if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=expected:
        raise SystemExit('FAIL '+rel)
sources=json.loads((root/'provenance/board_sources.json').read_text())['files']
for name, sha in sources.items(): check(name, sha)
for line in (root/'soc/bosio_sources.f').read_text().splitlines():
    if line.strip() and not (root/line.strip()).is_file(): raise SystemExit('Missing '+line)
for entry in json.loads((root/'software/linux/source_manifest.json').read_text())['changes']:
    check('software/linux/modified/'+entry['path'],entry['sha256'])
for entry in json.loads((root/'provenance/trace_v2_image.json').read_text())['segments']:
    check('software/firmware/'+entry['file'],entry['sha256'])
print(f'PASS 보드 입력 {len(sources)}개, Linux 수정 파일, 부팅 페이로드 일치')
