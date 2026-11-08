from pathlib import Path
import subprocess,re
root=Path(__file__).resolve().parents[2]
out=root/'soc/reports/xsim_fabric'
out.mkdir(parents=True,exist_ok=True)
bin_dir=Path('D:/Xilinx2202/Vivado/2022.2/bin')
names=['soc/bosio/or_bo_axi_pkg.sv','soc/bosio/or_bo_cdc_mailbox.sv','soc/bosio/or_bo_xpm_mailbox.sv','soc/bosio/or_bo_axi_cdc.sv','soc/bosio/or_bo_axi_fabric.sv','soc/bosio/gen3_bosio_status.sv','soc/tests/axi_ram_model.sv','soc/tests/axi_lite_test_slave.sv','soc/tests/tb_axi_fabric.sv']
(out/'sources.prj').write_text(''.join(f'sv work "{(root/n).as_posix()}"\n' for n in names)+'verilog work "D:/Xilinx2202/Vivado/2022.2/data/verilog/src/glbl.v"\n')
(out/'run.tcl').write_text('run all\nquit\n')
def run(tool,*args):
    with (out/(tool+'_console.log')).open('w') as log:
        subprocess.run([str(bin_dir/(tool+'.bat')),*args],cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True)
run('xvlog','-prj','sources.prj')
for mode in ('fabric',):
    run('xelab','-L','xpm','-L','unisims_ver','tb_axi_fabric','glbl','-s',mode+'_cdc','-debug','typical','-timescale','1ns/1ps')
    for seed in (1,7,23):
        name=f'{mode}_seed{seed}.log'
        (out/'options.txt').write_text(f'--testplusarg seed={seed}\n')
        run('xsim',mode+'_cdc','-tclbatch','run.tcl','-f','options.txt','-log',name)
        log=(out/name).read_text()
        assert 'PASS AXI_FABRIC' in log and not re.search(r'Fatal:|Error:|ERROR:',log),name
        print(mode+'\n'+'\n'.join(line for line in log.splitlines() if line.startswith('PASS ')),flush=True)
