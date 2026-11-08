from pathlib import Path
import subprocess,re
root=Path(__file__).resolve().parents[3]
out=root/'soc/reports/coldboot/bridge_xsim'
out.mkdir(parents=True,exist_ok=True)
bin_dir=Path('D:/Xilinx2202/Vivado/2022.2/bin')
names=['soc/bosio/or_bo_axi_pkg.sv','soc/bosio/or_bo_cpu_axi.sv',
       'soc/tests/axi_ram_model.sv','soc/tests/tb_cpu_axi_independent.sv',
       'soc/tests/tb_fetch_bridge.sv']
(out/'sources.prj').write_text(''.join(f'sv work "{(root/n).as_posix()}"\n' for n in names))
(out/'run.tcl').write_text('run all\nquit\n')
def run(tool,*args):
    with (out/(tool+'_console.log')).open('w') as log:
        subprocess.run([str(bin_dir/(tool+'.bat')),*args],cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True)
run('xvlog','-prj','sources.prj')
for top,marker in [('tb_cpu_axi_independent','PASS ALL_CPU_AXI_INDEPENDENT'),('tb_fetch_bridge','PASS ALL_FETCH_BRIDGE')]:
    run('xelab',top,'-s',top,'-debug','typical','-timescale','1ns/1ps')
    for seed in (1,7,23):
        name=f'{top}_seed{seed}.log'
        (out/'options.txt').write_text(f'--testplusarg seed={seed}\n')
        run('xsim',top,'-tclbatch','run.tcl','-f','options.txt','-log',name)
        text=(out/name).read_text()
        assert marker in text and not re.search(r'Fatal:|Error:|ERROR:',text),name
        print('\n'.join(line for line in text.splitlines() if line.startswith('PASS ')),flush=True)
