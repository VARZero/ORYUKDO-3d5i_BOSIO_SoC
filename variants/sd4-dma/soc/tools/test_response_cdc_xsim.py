"""Four-state check of the actual response CDC RTL; no replacement model."""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[2]
out = root/'soc/reports/xsim_response_cdc'
out.mkdir(exist_ok=True)
bin_dir = Path('D:/Xilinx2202/Vivado/2022.2/bin')
names = ['soc/bosio/or_bo_cdc_mailbox.sv','soc/tests/tb_response_cdc.sv']
(out/'sources.prj').write_text(''.join(f'sv work "{(root/n).as_posix()}"\n' for n in names))
(out/'run.tcl').write_text('run all\nquit\n')
def run(tool,*args):
    with (out/(tool+'_console.log')).open('w') as log:
        subprocess.run([str(bin_dir/(tool+'.bat')),*args],cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True)
run('xvlog','-prj','sources.prj')
run('xelab','tb_response_cdc','-s','response_cdc','-debug','typical','-timescale','1ns/1ps')
for seed in (1,7,23):
    name=f'seed{seed}.log'
    (out/'options.txt').write_text(f'--testplusarg seed={seed}\n')
    run('xsim','response_cdc','-tclbatch','run.tcl','-f','options.txt','-log',name)
    log=(out/name).read_text()
    assert 'PASS RESPONSE_CDC' in log and 'Fatal:' not in log, name
    print(next(line for line in log.splitlines() if line.startswith('PASS RESPONSE_CDC')))
