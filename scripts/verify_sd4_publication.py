"""SD4 공개 소스·증거의 무결성을 확인한다. 보드 동작 검증은 수행하지 않는다."""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]/'variants/sd4-dma'
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
sources=json.loads((root/'provenance/source_sha256.json').read_text())
for name,digest in sources.items():
 assert sha(root/name)==digest,'검증 소스와 다름: '+name
for line in (root/'soc/bosio_sources.f').read_text().splitlines():
 if line.strip():assert (root/line.strip()).is_file(),'없는 RTL 입력: '+line
files=json.loads((root/'provenance/publication_files.json').read_text())
for name,digest in files.items():
 assert sha(root/name)==digest,'게시 파일과 다름: '+name
status=json.loads((root/'validation/status.json').read_text())
assert all(check['pass_marker'] for check in status['checks'].values())
assert status['actual_image_loader']['current_rtl_matches']
assert status['full_board']['source_match'] and status['full_board']['route_pass_marker']
board=json.loads((root/'provenance/board_manifest.json').read_text())
assert board['hardware_tested'] is False
assert board['timing_ns']['wns']>=0 and board['timing_ns']['whs']>=0
assert board['timing_ns']['tns']==0 and board['timing_ns']['ths']==0
assets=json.loads((root/'provenance/release_assets.json').read_text())['assets']
for key in ('image','bitstream'):
 asset=next(a for a in assets if a['name']==board[key])
 assert asset['sha256']==board[key+'_sha256']
assert json.loads((root/'validation/actual_image_loader.json').read_text())['image_sha256']==board['image_sha256']
assert json.loads((root/'validation/qemu_shell/result.json').read_text())['image_sha256']==board['image_sha256']
print(f'PASS SD4 검증 소스 {len(sources)}개, 게시 파일 {len(files)}개, 기능시험 기록, 배선 결과 및 이미지 대응')
print('실보드 MMC/ext4 검증은 아직 수행하지 않았습니다.')
