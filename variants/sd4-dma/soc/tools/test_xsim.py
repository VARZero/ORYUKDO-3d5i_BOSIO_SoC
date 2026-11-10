"""Cross-check the actual CPU/BOSIO workload in four-state simulation.
Run test.sh first to build the RV32 probe, or supply an existing probe.hex.
XSIM can exit zero after $fatal; the PASS marker is mandatory.
"""
from pathlib import Path
import argparse, subprocess

root = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser()
p.add_argument('--bin', default='D:/Xilinx2202/Vivado/2022.2/bin')
p.add_argument('--out', type=Path, default=root/'soc/reports/xsim_final')
p.add_argument('--io-trace', action='store_true')
p.add_argument('--operand-check', action='store_true')
p.add_argument('--render-check', action='store_true')
p.add_argument('--seed', type=int, default=1)
p.add_argument('--pattern-scene', action='store_true')
p.add_argument('--cpu-source', type=Path, help='Diagnostic A/B run: override only gen3_cpu.sv')
p.add_argument('--native-backend', action='store_true')
args = p.parse_args()
out = args.out.resolve(); out.mkdir(parents=True, exist_ok=True)
image = root/('soc/reports/probe_patterned.hex' if args.pattern_scene else 'soc/reports/probe.hex')
assert image.exists(), 'Build firmware with test.sh first'
names = (root/'soc/bosio_sources.f').read_text().splitlines()
names += (['soc/board/kfb_axi_mig.sv','soc/board/kfb_native_arbiter.sv','soc/tests/kfb_native_ram_model.sv','soc/tests/kfb_axi_ram_model.sv'] if args.native_backend else ['soc/tests/axi_ram_model.sv']) + ['soc/tests/tb_gen3_bosio.sv']
source_paths = [args.cpu_source.resolve() if args.cpu_source and n=='soc/rtl/gen3_cpu.sv'
                else root/n for n in names]
(out/'sources.prj').write_text('\n'.join(
    ('sv' if f.suffix=='.sv' else 'verilog')+' work "'+f.as_posix()+'"' for f in source_paths)+'\n')
with (out/'sources.prj').open('a') as f: f.write('verilog work "D:/Xilinx2202/Vivado/2022.2/data/verilog/src/glbl.v"\n')
(out/'run.tcl').write_text('run all\nquit\n')
(out/'options.txt').write_text('--testplusarg "image='+ image.as_posix()+'"\n'+ ('--testplusarg io_trace\n' if args.io_trace else '') + ('--testplusarg operand_check\n' if args.operand_check else '') + ('--testplusarg pattern_scene\n' if args.pattern_scene else '') + f'--testplusarg seed={args.seed}\n')
if args.render_check:
    with (out/'options.txt').open('a') as f: f.write('--testplusarg render_check\n')
def run(name, *argv):
    with (out/(name+'_console.log')).open('w') as log:
        subprocess.run([str(Path(args.bin)/(name+'.bat')), *argv], cwd=out,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
run('xvlog', '-prj', 'sources.prj', *(['-d','KFB_NATIVE_BACKEND'] if args.native_backend else []))
run('xelab', '-L', 'xpm', '-L', 'unisims_ver', 'tb_gen3_bosio', 'glbl', '-s', 'gen3_bosio', '-debug', 'typical', '-mt', '4', '-timescale', '1ns/1ps')
run('xsim', 'gen3_bosio', '-tclbatch', 'run.tcl', '-f', 'options.txt', '-log', 'integration.log')
log = (out/'integration.log').read_text()
assert 'PASS GEN3_BOSIO' in log and 'Fatal:' not in log, 'XSIM workload failed; inspect integration.log'
print('PASS XSIM GEN3_BOSIO', out/'integration.log')
