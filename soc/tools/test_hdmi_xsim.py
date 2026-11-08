from pathlib import Path
import subprocess,re
root=Path(__file__).resolve().parents[2]
out=root/'soc/reports/hdmi_official_xsim';out.mkdir(parents=True,exist_ok=True)
bin_dir=Path('D:/Xilinx2202/Vivado/2022.2/bin')
def run(tool,*args):
    with (out/(tool+'_console.log')).open('w') as log:
        subprocess.run([str(bin_dir/(tool+'.bat')),*args],cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True)
vhdl=[root/'soc/board/vendor/digilent_rgb2dvi/src'/p for p in
      ('DVI_Constants.vhd','SyncAsync.vhd','SyncAsyncReset.vhd','ClockGen.vhd',
       'TMDS_Encoder.vhd','OutputSERDES.vhd','rgb2dvi.vhd')]
run('xvhdl',*[str(p) for p in vhdl])
run('xvlog','-sv',str(root/'soc/board/kfb_hdmi.sv'),str(root/'soc/tests/tb_kfb_hdmi.sv'),'D:/Xilinx2202/Vivado/2022.2/data/verilog/src/glbl.v')
run('xelab','-L','xpm','-L','unisim','-L','unisims_ver','tb_kfb_hdmi','glbl','-s','hdmi','-debug','typical','-timescale','1ns/1ps')
(out/'run.tcl').write_text('run all\nquit\n')
run('xsim','hdmi','-tclbatch','run.tcl','-log','hdmi.log')
log=(out/'hdmi.log').read_text()
assert 'PASS KFB_HDMI' in log and not re.search(r'Fatal:|Error:|ERROR:',log), 'HDMI check failed'
print('\n'.join(s for s in log.splitlines() if s.startswith('PASS ')))
