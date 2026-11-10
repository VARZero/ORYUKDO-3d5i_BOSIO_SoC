from pathlib import Path
import tarfile,hashlib,json,sys
root=Path(__file__).resolve().parents[2]
archive=Path(sys.argv[1])
expected={f'linux/drivers/{directory}/{name}':(root/'software/storage'/name).read_bytes()
          for directory,name in [('mmc/host','oryukdo_sd.c'),('dma','oryukdo_dma.c')]}
found=[];files=0;size=0
with tarfile.open(archive,'r|gz') as tar:
 for member in tar:
  if member.issym():assert not member.linkname.startswith('/'),member.name
  if member.isfile():files+=1;size+=member.size
  if member.name in expected:
   assert tar.extractfile(member).read()==expected[member.name];found.append(member.name)
assert len(found)==2
h=hashlib.sha256()
with archive.open('rb') as f:
 for data in iter(lambda:f.read(1024*1024),b''):h.update(data)
report={'result':'PASS_SOURCE_ARCHIVE','path':str(archive),'sha256':h.hexdigest(),
        'regular_files':files,'uncompressed_file_bytes':size,'driver_matches':found,
        'external_absolute_symlinks':0}
(root/'validation/kernel_archive.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
