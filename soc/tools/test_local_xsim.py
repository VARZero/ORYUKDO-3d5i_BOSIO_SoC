from pathlib import Path
import subprocess,re
root=Path(__file__).resolve().parents[2]
out=root/'soc/reports/xsim_local';out.mkdir(parents=True,exist_ok=True)
bin_dir=Path('D:/Xilinx2202/Vivado/2022.2/bin')
names=['soc/bosio/or_bo_axi_pkg.sv','soc/bosio/or_bo_cpu_axi.sv','soc/vendor/output/bosio_out_fifo.v','soc/vendor/output/varzero_cache_line.v','soc/tests/tb_fetch_bridge.sv','soc/tests/tb_ram_reset.sv']
(out/'sources.prj').write_text(''.join(f'sv work "{(root/n).as_posix()}"\n' for n in names))
(out/'run.tcl').write_text('run all\nquit\n')
def run(tool,*args):
    with (out/(tool+'_console.log')).open('w') as log:
        subprocess.run([str(bin_dir/(tool+'.bat')),*args],cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True)
run('xvlog','-prj','sources.prj')
for mode,top,seeds,marker in [('fetch','tb_fetch_bridge',(1,7,23),'PASS ALL_FETCH_BRIDGE'),('ram_reset','tb_ram_reset',(1,),'PASS RAM_RESET')]:
    run('xelab',top,'-s',mode,'-debug','typical','-timescale','1ns/1ps')
    for seed in seeds:
        name=f'fetch_seed{seed}.log' if mode=='fetch' else 'ram_reset.log'
        (out/'options.txt').write_text(f'--testplusarg seed={seed}\n')
        run('xsim',mode,'-tclbatch','run.tcl','-f','options.txt','-log',name)
        text=(out/name).read_text()
        assert marker in text and not re.search(r'Fatal:|Error:|ERROR:',text),name
        print('\n'.join(line for line in text.splitlines() if line.startswith('PASS ')),flush=True)
