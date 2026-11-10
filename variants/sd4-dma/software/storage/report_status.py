"""Collect evidence without restarting builds or accessing the board."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re,sys
root=Path(__file__).resolve().parents[2]
out=Path(sys.argv[1])
board=Path(sys.argv[2])
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text()) if p.is_file() else None
def text(p):return p.read_text(errors='replace') if p.is_file() else ''
logs=['native_test.log','native_delayed_input_test.log','storage_test.log',
      'soc_lint_summary.log','cpu_bosio_regression.log']
logs += [f'{test}_seed{seed}.log' for test in ('dma','plic','irq') for seed in (1,7,23)]
logs += [f'cpu_storage_seed{seed}.log' for seed in (1,7,23)]
logs += [f'cpu_storage_native_seed{seed}.log' for seed in (1,7,23)]
logs += ['cpu_bosio_native_regression.log']
logs += [f'boot_reject_{name}.log' for name in ('header','oversize','payload-crc','card-crc','ddr')]
checks={}
for name in logs:
 p=root/'validation'/name;s=text(p)
 expected=6 if name in ('cpu_bosio_regression.log','cpu_bosio_native_regression.log') else 2 if name=='storage_test.log' or name.startswith('cpu_storage_native_seed') else 1
 count=len(re.findall(r'^PASS\b',s,re.M))
 failed=bool(re.search(r'(^FAIL\b|%Fatal|%Error|Assertion failed|Aborting)',s,re.M))
 checks[name]={'pass_marker':count>=expected and not failed,'pass_count':count,'expected_count':expected,
               'sha256':sha(p) if p.is_file() else None}
loader=load(root/'validation/actual_image_loader.json')
if loader:
 loader['current_rtl_matches']=all(sha(root/name)==digest for name,digest in loader['rtl_sha256'].items())
manifest=load(board/'source_manifest.json')
sources_match=None
if manifest:
 def host_path(p):
  return Path('/mnt/'+p[0].lower()+p[2:].replace('\\','/')) if sys.platform!='win32' and p[1]==':' else Path(p)
 sources_match=all(host_path(p).is_file() and sha(host_path(p))==h for p,h in manifest.items())
runner=text(board.parent/(board.name+'_runner.log'))
report={
 'updated_utc':datetime.now(timezone.utc).isoformat(),
 'release':'CANDIDATE_NOT_HARDWARE_VALIDATED',
 'board_accessed':False,'original_worktree':'work/bosio-linux-sw preserved',
 'image':str(out/'ORYUKDO-KFB-SD4-DMA-v1.img'),
 'image_sha256':sha(out/'ORYUKDO-KFB-SD4-DMA-v1.img'),
 'checks':checks,'actual_image_loader':loader,
 'qemu':load(root/'validation/qemu_shell/result.json'),
 'full_board':{'directory':str(board),'source_match':sources_match,
  'synth_pass_marker':'PASS KFB_BOSIO_BOARD_SYNTHESIS' in runner,
  'route_pass_marker':'PASS KFB_BOSIO_BOARD_ROUTE ' in runner,
  'error_in_runner':'Traceback' in runner or 'ERROR:' in runner,
  'bitstream_exists':(board/'route/ORYUKDO-Gen3-BOSIO-KFB.bit').is_file()},
 'pending_hardware':['native MMC enumeration','ext4 mount/write/reboot persistence',
  'actual card/PCB timing and bandwidth','DMAengine software execution on FPGA'],
 'not_proven':['full RTL CPU boots this Linux image to shell','BoAYO accelerated by DMA'],
}
(root/'validation/status.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report['full_board'],indent=2))
