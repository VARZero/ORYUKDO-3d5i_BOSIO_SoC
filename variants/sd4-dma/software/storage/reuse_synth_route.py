"""Try physical implementation with a verified, unchanged synthesized netlist."""
from pathlib import Path
import argparse,hashlib,json,shutil,subprocess
p=argparse.ArgumentParser()
p.add_argument('base',type=Path);p.add_argument('out',type=Path)
p.add_argument('--reference',required=True,type=Path)
a=p.parse_args();base=a.base.resolve();out=a.out.resolve();ref=a.reference.resolve()
root=Path(__file__).resolve().parents[2];here=root/'soc/board'
def sha(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
 return h.hexdigest()
assert not out.exists(),'Use a new output directory'
assert ref.is_file()
sources=json.loads((base/'source_manifest.json').read_text())
for name,digest in sources.items():assert sha(Path(name))==digest,'Source changed: '+name
assert '\nPASS KFB_BOSIO_BOARD_SYNTHESIS\n' in (base/'synth_console.log').read_text()
dcp=base/'synth/optimized.dcp';assert dcp.is_file()
sources[str(Path(__file__).resolve())]=sha(Path(__file__))
(out/'synth').mkdir(parents=True);(out/'route').mkdir()
(out/'source_manifest.json').write_text(json.dumps(sources,indent=2)+'\n')
for source in (base/'synth').glob('*.rpt'):shutil.copy2(source,out/'synth'/source.name)
shutil.copy2(base/'synth_console.log',out/'synth_console.log')
inputs=dict(sources);inputs[str(dcp)]=sha(dcp);inputs[str(ref)]=sha(ref)
(out/'route/implementation_inputs.json').write_text(json.dumps({
 'input_hashes':inputs,'strategy':'incremental with guarded DSP pipelines',
 'reused_synthesis':str(base),'reference_routed_checkpoint':str(ref),
 'scope':'Physical reuse only; current RTL and current timing constraints retained; hardware untested'
},indent=2)+'\n')
print('PASS KFB_BOSIO_BOARD_SYNTHESIS (reused verified checkpoint)',flush=True)
with (out/'route_console.log').open('w') as log:
 subprocess.run(['D:/Xilinx2202/Vivado/2022.2/bin/vivado.bat','-mode','batch',
  '-source',str(here/'route_incremental.tcl'),'-log',str(out/'route.log'),
  '-journal',str(out/'route.jou'),'-tclargs',str(dcp),str(out/'route'),str(ref)],
  cwd=root,stdout=log,stderr=subprocess.STDOUT,check=True)
for name,digest in inputs.items():assert sha(Path(name))==digest,'Implementation input changed: '+name
assert '\nPASS KFB_BOSIO_BOARD_ROUTE ' in (out/'route_console.log').read_text()
print('PASS KFB_BOSIO_BOARD_ROUTE (reused synthesis, current sources verified)',flush=True)
