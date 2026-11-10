"""Collect reviewable local artifacts and record exact source identities."""
from pathlib import Path
import hashlib,json,shutil,subprocess,sys,tarfile

root=Path(__file__).resolve().parents[2]
build=Path(sys.argv[1] if len(sys.argv)>1 else '/var/tmp/oryukdo-sd4-linux')
out=Path(sys.argv[2] if len(sys.argv)>2 else '/mnt/d/temp/gen3bosio/sd4-dma/candidate')
out.mkdir(parents=True,exist_ok=True)
for src,dst in [(build/'image/ORYUKDO-KFB-SD4-DMA-v1.img','ORYUKDO-KFB-SD4-DMA-v1.img'),
                (build/'image/manifest.json','image_manifest.json'),
                (build/'image/boot/manifest.json','boot_manifest.json'),
                (build/'kernel/.config','kernel.config'),(build/'kernel.log','kernel_build.log'),
                (build/'image.log','image_build_verify.log'),
                (build/'firmware/Image','Image'),(build/'firmware/gen3.dts','gen3.dts'),
                (build/'image/boot/gen3.dtb','gen3.dtb'),(build/'firmware/fw_jump.bin','fw_jump.bin')]:
    shutil.copy2(src,out/dst)
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
    return h.hexdigest()
sources={}
for d in ('rtl','gen2','soc','software/storage'):
    for p in sorted((root/d).rglob('*')):
        if p.is_file() and p.suffix in ('.sv','.v','.vhd','.xdc','.tcl','.cpp','.hpp','.f','.c','.h','.sh','.py'):
            sources[str(p.relative_to(root))]=sha(p)
sources['software/bosio/gen3-bosio.dts']=sha(root/'software/bosio/gen3-bosio.dts')
(out/'source_sha256.json').write_text(json.dumps(sources,indent=2)+'\n')
for name,where in [('oryukdo_sd.c','drivers/mmc/host'),('oryukdo_dma.c','drivers/dma')]:
    assert sha(root/'software/storage'/name)==sha(build/'linux'/where/name),name
assert sha(root/'software/bosio/gen3-bosio.dts')==sha(build/'firmware/gen3.dts')
assert sha(out/'ORYUKDO-KFB-SD4-DMA-v1.img')==json.loads((out/'image_manifest.json').read_text())['sha256']
baseline=Path('/var/tmp/oryukdo-boayo-native-v2-final/root')
preserved={}
for name in ('bin/busybox','usr/bin/boayo-native'):
    assert sha(baseline/name)==sha(build/'root'/name)
    preserved[name]=sha(build/'root'/name)
(out/'preserved_userspace.json').write_text(json.dumps(preserved,indent=2)+'\n')
shutil.copy2(root/'README_STORAGE_KO.md',out/'README_STORAGE_KO.md')
shutil.copy2(root/'BOARD_STORAGE_CHECK_KO.md',out/'BOARD_STORAGE_CHECK_KO.md')
with tarfile.open(out/'ORYUKDO-SD4-DMA-rtl-software-tests.tar.gz','w:gz') as tar:
    for directory in ('rtl','gen2','soc','scripts','software/storage','software/bosio','software/linux','validation'):
        for p in sorted((root/directory).rglob('*')):
            relative=p.relative_to(root)
            if not p.is_file() or any(part in ('reports','__pycache__','.git','obj_dir') for part in relative.parts):continue
            if p.suffix in ('.vcd','.fst','.pyc'):continue
            tar.add(p,arcname=str(relative),recursive=False)
    for name in ('README_STORAGE_KO.md','BOARD_STORAGE_CHECK_KO.md','software/firmware/fw_jump.bin'):
        tar.add(root/name,arcname=name,recursive=False)
(out/'package_sha256.json').write_text(json.dumps({p.name:sha(p) for p in out.iterdir()
    if p.is_file() and p.suffix in ('.img','.gz','.bin','.dtb','.bit')},indent=2)+'\n')
print('PASS candidate image hash, driver/DTS source match, preserved BusyBox and BoAYO-v2')
