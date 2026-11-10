"""Raw boot + aligned ext4 /data. Never opens a physical disk."""
import argparse, hashlib, json, shutil, struct, subprocess
from pathlib import Path

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('out',type=Path)
    ap.add_argument('--firmware',type=Path,required=True)
    ap.add_argument('--data-mib',type=int,default=256)
    ap.add_argument('--data-root',type=Path)
    args=ap.parse_args()
    if args.data_mib<32 or args.data_mib>16384:
        ap.error('data-mib must be 32..16384')
    root=Path(__file__).resolve().parents[2]
    args.out.mkdir(parents=True,exist_ok=True)
    raw=args.out/'boot'
    subprocess.run(['python3',str(root/'soc/board/make_sd.py'),str(raw),'--firmware',str(args.firmware)],check=True)
    boot=raw/'ORYUKDO-Gen3-BOSIO-KFB-1GiB-BusyBox.img'
    subprocess.run(['python3',str(root/'soc/board/verify_image.py'),str(boot),str(args.firmware),str(raw/'gen3.dtb')],check=True)
    first=((boot.stat().st_size//512+2047)//2048)*2048
    sectors=args.data_mib*2048
    ext=args.out/'data.ext4'
    with ext.open('wb') as f:f.truncate(args.data_mib*1024*1024)
    command=['mkfs.ext4','-q','-F','-b','4096','-L','ORYDATA']
    if args.data_root:command+=['-d',str(args.data_root)]
    subprocess.run(command+[str(ext)],check=True)
    subprocess.run(['e2fsck','-fn',str(ext)],check=True)
    target=args.out/'ORYUKDO-KFB-SD4-DMA-v1.img'
    with target.open('wb') as dst,boot.open('rb') as src:
        shutil.copyfileobj(src,dst)
        dst.seek(first*512)
        with ext.open('rb') as data:shutil.copyfileobj(data,dst)
        dst.seek(462)
        dst.write(struct.pack('<B3sB3sII',0,bytes.fromhex('feffff'),0x83,bytes.fromhex('feffff'),first,sectors))
    # Check image's actual MBR and ext4 superblock, independent of mkfs output.
    with target.open('rb') as f:
        mbr=f.read(512)
        p1=struct.unpack_from('<B3sB3sII',mbr,446)
        p2=struct.unpack_from('<B3sB3sII',mbr,462)
        assert mbr[510:512]==b'\x55\xaa' and p1[2]==0xda and p2[2]==0x83
        assert p1[4]==2048 and p1[4]+p1[5]<=p2[4]
        assert (p2[4]+p2[5])*512==target.stat().st_size
        f.seek(first*512+1024+56);assert f.read(2)==b'\x53\xef'
        f.seek(2048*512);assert f.read(8)==b'ORYSD001'
    h=hashlib.sha256()
    with target.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
    manifest={'image':str(target),'sha256':h.hexdigest(),'bytes':target.stat().st_size,
              'boot_lba':2048,'data_lba':first,'data_sectors':sectors,'data_fs':'ext4',
              'mount':'/data','hardware_tested':False,
              'requires':'SD4 native bitstream; incompatible with SPI-only runtime'}
    (args.out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('PASS boot CRCs, MBR non-overlap, ext4 filesystem: '+json.dumps(manifest))
if __name__=='__main__':main()
