"""Reproduce synthesis and routing using the separately generated, unchanged MIG IP."""
from pathlib import Path
import argparse,hashlib,json,subprocess
from verify_vendor import verify
p=argparse.ArgumentParser()
p.add_argument('out',type=Path)
p.add_argument('--ip',required=True,type=Path,help='Generated mig_7series_0.xci')
p.add_argument('--vivado',default='D:/Xilinx2202/Vivado/2022.2/bin/vivado.bat')
p.add_argument('--strategy',choices=('default','spread','area','area-medium','area-medium-guarded','area-medium-incremental'),default='default',
               help='Default routing, spread placement, ExploreArea optimization, or AreaOptimized_medium synthesis')
p.add_argument('--reference',type=Path,help='Accepted routed checkpoint for area-medium-incremental')
args=p.parse_args()
if args.strategy=='area-medium-incremental' and not (args.reference and args.reference.is_file()):
    p.error('area-medium-incremental requires --reference routed.dcp')
verify()
here=Path(__file__).resolve().parent;root=here.parents[1]
out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
sources=[root/n for n in (root/'soc/bosio_sources.f').read_text().splitlines() if n.strip()]
sources+=list(here.glob('*.sv'))+list(here.glob('*.xdc'))+list(here.glob('*.tcl'))
sources+=list((here/'vendor/digilent_rgb2dvi/src').glob('*'))
sources+=[here/'vendor/digilent_rgb2dvi/upstream_sources.json',here/'mig_a.prj',args.ip.resolve()]
def hashes():
    return {str(f.resolve()):hashlib.sha256(f.read_bytes()).hexdigest() for f in sources}
before=hashes()
(out/'source_manifest.json').write_text(json.dumps(before,indent=2)+'\n')
synth_script='build_area_medium_synth.tcl' if args.strategy.startswith('area-medium') else 'build_board.tcl'
stages=[('synth',synth_script,[str(out/'synth'),str(args.ip.resolve())],
         'PASS KFB_BOSIO_BOARD_SYNTHESIS')]
checkpoint=out/'synth/optimized.dcp'
if args.strategy=='area':
    stages.append(('area','probe_area.tcl',[str(checkpoint),str(out/'area')],
                   'PASS KFB_AREA_PROBE_ONLY'))
    checkpoint=out/'area/area.dcp'
route_script='route_spread.tcl' if args.strategy=='spread' else 'route_board.tcl'
if args.strategy=='area-medium-guarded':route_script='route_guarded.tcl'
route_extra=[]
if args.strategy=='area-medium-incremental':
    route_script='route_incremental.tcl'
    route_extra=[str(args.reference.resolve())]
stages.append(('route',route_script,[str(checkpoint),str(out/'route'),*route_extra],
               'PASS KFB_BOSIO_BOARD_ROUTE'))
for stage,script,extra,marker in stages:
    if stage=='route':
        route_inputs=dict(before)
        if args.strategy=='area-medium-incremental':
            route_inputs[str(args.reference.resolve())]=hashlib.sha256(args.reference.read_bytes()).hexdigest()
        for dcp in {out/'synth/optimized.dcp',checkpoint}:
            route_inputs[str(dcp)]=hashlib.sha256(dcp.read_bytes()).hexdigest()
        (out/'route').mkdir(exist_ok=True)
        (out/'route/implementation_inputs.json').write_text(json.dumps({
            'input_hashes':route_inputs,'strategy':args.strategy,
            'scope':'Full-board implementation; hardware operation unverified'},indent=2)+'\n')
    with (out/(stage+'_console.log')).open('w') as log:
        subprocess.run([args.vivado,'-mode','batch','-source',str(here/script),
            '-log',str(out/(stage+'.log')),'-journal',str(out/(stage+'.jou')),'-tclargs',*extra],
            cwd=root,stdout=log,stderr=subprocess.STDOUT,check=True)
    if hashes()!=before:raise RuntimeError('Build inputs changed during execution')
    verify()
    if marker not in (out/(stage+'_console.log')).read_text():raise RuntimeError('Missing '+marker)
    print(marker,flush=True)
