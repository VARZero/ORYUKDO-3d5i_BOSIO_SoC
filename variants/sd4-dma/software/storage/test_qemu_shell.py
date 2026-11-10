"""Boot exact firmware/kernel/DTB payloads on QEMU; no native SD/MIG/ORYUKDO CPU emulation. /data mount is expected to fail because the SD controller is absent."""
from pathlib import Path
import sys,subprocess,tempfile,struct,zlib,selectors,time,os,re,json,hashlib
image=Path(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
boot_only=True
data=image.read_bytes();header=2048*512;assert data[header:header+8]==b'ORYSD001'
report=dict(result='RUNNING',image=str(image),image_sha256=hashlib.sha256(data).hexdigest(),hardware=False,rtl=False,mock_backend=True,checks=[])
with tempfile.TemporaryDirectory(prefix='boayo-native-qemu-') as temp,(out/'uart.log').open('wb') as log:
 root=Path(temp);cmd=['qemu-system-riscv32','-machine','virt','-cpu','rv32,c=false,f=false,d=false,v=false,zfa=false,zawrs=false','-m','1G','-smp','1','-bios','none','-display','none','-monitor','none','-serial','stdio','-no-reboot']
 pos=header+512
 for n,(name,address) in enumerate([('fw',0x80000000),('kernel',0x80400000),('dtb',0x87f00000)]):
  count,crc=struct.unpack_from('<II',data,header+8+n*8);payload=data[pos:pos+count*512];pos+=count*512;assert zlib.crc32(payload)==crc
  path=root/name;path.write_bytes(payload);cmd+=['-device',f'loader,file={path},addr={address},force-raw=on']
 (root/'entry').write_bytes(struct.pack('<4I',0x00000513,0x87f005b7,0x800002b7,0x00028067));cmd+=['-device',f'loader,file={root/"entry"},addr=0x80200000,force-raw=on,cpu-num=0']
 process=subprocess.Popen(cmd,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,bufsize=0)
 sel=selectors.DefaultSelector();sel.register(process.stdout,selectors.EVENT_READ);buffer=bytearray()
 def until(pattern,timeout=600):
  end=time.monotonic()+timeout
  while True:
   hit=re.search(pattern,buffer)
   if hit:r=bytes(buffer[:hit.end()]);del buffer[:hit.end()];return r
   if not sel.select(max(0,end-time.monotonic())):raise TimeoutError(pattern)
   chunk=os.read(process.stdout.fileno(),16384)
   if not chunk:raise RuntimeError('QEMU exited')
   log.write(chunk);log.flush();buffer.extend(chunk)
   if b'Kernel panic' in buffer:raise RuntimeError('Kernel panic')
 def run(command,pattern=b'oryukdo# ',timeout=600):
  process.stdin.write((command+'; echo __NATIVE_RC:$?\r').encode());reply=until(rb'oryukdo# ',timeout)
  assert re.search(rb'\n__NATIVE_RC:0\r*\n',reply),(command,reply)
  assert re.search(pattern,reply),(command,reply)
  report['checks'].append(command);print('PASS_QEMU '+command,flush=True);return reply
 try:
  until(rb'oryukdo# ');report['checks'].append('BusyBox repair shell; native SD hardware absent')
  run('cat /etc/oryukdo-image',rb'ORYUKDO-SD4-DMA-v1')
  run('test ! -L /usr/bin/python && test ! -e /usr/bin/python3 && test ! -d /usr/lib/python3.12')
  run('echo $((19+23))',rb'\n42\r*\n')
  run('ddrcheck',rb'DDR_HIGH_OK pages=16')
  run('test -x /bin/storage-check && test -d /data')
  report['result']='PASS_QEMU_ONLY'
 except BaseException as exc:
  report['result']='FAIL';report['error']=repr(exc);raise
 finally:
  process.terminate()
  try:process.wait(timeout=5)
  except subprocess.TimeoutExpired:process.kill();process.wait()
  (out/'result.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report),flush=True)
