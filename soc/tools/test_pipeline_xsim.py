from pathlib import Path
import subprocess,re
root=Path(__file__).resolve().parents[2]
out=root/'soc/reports/xsim_pipeline';out.mkdir(parents=True,exist_ok=True)
bin_dir=Path('D:/Xilinx2202/Vivado/2022.2/bin')
jobs=[
 ('math','tb_pipeline_math',['soc/rtl/gen3_mul33_pipe.sv','soc/vendor/projection/bosio_projector_mul_mul_8ns_25ns_32_4_1.v','soc/tests/tb_pipeline_math.sv'],(1,7,23)),
 ('pose','tb_pose_equivalence',['soc/rtl/gen3_mul33_pipe.sv','soc/tests/baseline_sensor_pose.v','soc/vendor/output/bosio_v2_sensor_pose.v','soc/tests/tb_pose_equivalence.sv'],(1,)),
 ('md','tb_muldiv_equivalence',['soc/rtl/rv32_pkg.sv','soc/rtl/gen3_mul33_pipe.sv','soc/rtl/rv32_muldiv.sv','soc/tests/baseline_muldiv.sv','soc/tests/tb_muldiv_equivalence.sv'],(1,7,23)),
 ('banks','tb_projector_banks',['soc/vendor/output/bosio_v2_projector.v','soc/tests/tb_projector_banks.sv'],(1,)),
 ('sensor','tb_sensor_link',[p.relative_to(root).as_posix() for p in (root/'soc/vendor/sensor').glob('*.v')]+['soc/vendor/output/bosio_out_sensor_rx.v','soc/tests/tb_sensor_link.sv'],(1,))]
def run(tool,*args):
 with (out/(tool+'_console.log')).open('w') as f:
  subprocess.run([str(bin_dir/(tool+'.bat')),*args],cwd=out,stdout=f,stderr=subprocess.STDOUT,check=True)
(out/'run.tcl').write_text('run all\nquit\n')
for mode,top,names,seeds in jobs:
 (out/'sources.prj').write_text(''.join(f'sv work "{(root/n).as_posix()}"\n' for n in names))
 # Separate libraries prevent duplicate reference module definitions.
 run('xvlog','-prj','sources.prj')
 run('xelab',top,'-s',mode,'-debug','typical','-timescale','1ns/1ps')
 for seed in seeds:
  logname=f'{mode}_seed{seed}.log'
  (out/'options.txt').write_text(f'--testplusarg seed={seed}\n')
  run('xsim',mode,'-tclbatch','run.tcl','-f','options.txt','-log',logname)
  text=(out/logname).read_text()
  assert re.search(r'^PASS ',text,re.M) and not re.search(r'Fatal:|Error:|ERROR:',text),logname
  print('\n'.join(re.findall(r'^PASS .+$',text,re.M)),flush=True)
