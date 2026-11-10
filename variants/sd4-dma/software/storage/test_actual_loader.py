"""Run the real native SD boot RTL with release payloads and pin-level card model."""
from pathlib import Path
import hashlib,json,subprocess,sys
root=Path(__file__).resolve().parents[2]
build=Path(sys.argv[1] if len(sys.argv)>1 else '/var/tmp/oryukdo-sd4-linux')
image=build/'image/ORYUKDO-KFB-SD4-DMA-v1.img'
boot=build/'image/boot/ORYUKDO-Gen3-BOSIO-KFB-1GiB-BusyBox.img'
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()
before=sha(image)
with boot.open('rb') as a,image.open('rb') as b:
    a.seek(2048*512);b.seek(2048*512)
    payload=a.read();assert b.read(len(payload))==payload
with (root/'validation/actual_image_loader.log').open('w') as log:
    subprocess.run(['/var/tmp/oryukdo-sd4-storage-test/Vtb_sd_storage','image',str(boot)],
                   stdout=log,stderr=subprocess.STDOUT,check=True)
assert sha(image)==before
report={'result':'PASS_NATIVE_SD_LOADER_MODEL','image_sha256':before,'raw_boot_sha256':sha(boot),
        'hardware':False,'rtl':True,'cpu_executes_linux':False,
        'ddr_backend':'mock; loader RAM clear parameter reduced to 4096 bytes',
        'native_sd_model':'pin-level behavioral SDHC model',
        'rtl_sha256':{str(p.relative_to(root)):sha(p) for p in [
            root/'soc/board/sd_boot.sv',root/'soc/bosio/or_sd_native.sv',
            root/'soc/bosio/or_sd_storage.sv',root/'soc/bosio/or_storage_dma.sv']}}
(root/'validation/actual_image_loader.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
