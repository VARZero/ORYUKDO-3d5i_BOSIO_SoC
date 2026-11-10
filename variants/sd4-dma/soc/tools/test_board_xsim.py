from pathlib import Path
import subprocess,re,argparse
parser=argparse.ArgumentParser()
parser.add_argument('--video720p',action='store_true')
args=parser.parse_args()
root=Path(__file__).resolve().parents[2]
out=root/('soc/reports/board_xsim_720p' if args.video720p else 'soc/reports/board_xsim')
out.mkdir(parents=True,exist_ok=True)
bin_dir=Path('D:/Xilinx2202/Vivado/2022.2/bin')
names=['soc/bosio/or_bo_axi_pkg.sv','soc/board/kfb_axi_mig.sv','soc/board/kfb_native_arbiter.sv',
       'soc/board/kfb_video_fifo.sv','soc/board/kfb_video.sv','soc/tests/kfb_native_ram_model.sv',
       'soc/tests/tb_kfb_memory.sv','soc/tests/tb_kfb_video.sv']
(out/'sources.prj').write_text(''.join(f'sv work "{(root/n).as_posix()}"\n' for n in names)+
    'verilog work "D:/Xilinx2202/Vivado/2022.2/data/verilog/src/glbl.v"\n')
(out/'run.tcl').write_text('run all\nquit\n')
def run(tool,*args,tag=''):
    with (out/(tag+tool+'_console.log')).open('w') as log:
        subprocess.run([str(bin_dir/(tool+'.bat')),*args],cwd=out,stdout=log,stderr=subprocess.STDOUT,check=True)
run('xvlog','-prj','sources.prj',*(['-d','KFB_VIDEO_720P'] if args.video720p else []))
for mode in (('video',) if args.video720p else ('memory','video')):
    run('xelab','-L','xpm','-L','unisims_ver',f'tb_kfb_{mode}','glbl','-s',mode,'-debug','typical','-timescale','1ns/1ps',tag=mode)
    for seed in ((1,) if args.video720p else (1,7,23)):
        name=f'{mode}_seed{seed}.log'
        (out/'options.txt').write_text(f'--testplusarg seed={seed}\n')
        run('xsim',mode,'-tclbatch','run.tcl','-f','options.txt','-log',name,tag=mode+str(seed))
        log=(out/name).read_text()
        assert 'PASS KFB_' in log and not re.search(r'Fatal:|Error:|ERROR:',log),name
        print('\n'.join(line for line in log.splitlines() if line.startswith('PASS ')),flush=True)
