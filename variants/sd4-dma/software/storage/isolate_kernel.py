"""Materialize copied source links and undo only this task's appended hooks."""
from pathlib import Path
import shutil, json
root=Path('/var/tmp/oryukdo-sd4-linux/linux')
base=Path('/var/tmp/oryukdo-bosio-linux/linux')
suffixes={
 'drivers/mmc/host/Makefile':'\nobj-$(CONFIG_MMC_ORYUKDO) += oryukdo_sd.o\n',
 'drivers/mmc/host/Kconfig':'\nconfig MMC_ORYUKDO\n\tbool "ORYUKDO native SD host"\n\tdepends on MMC && RISCV\n',
 'drivers/dma/Makefile':'\nobj-$(CONFIG_ORYUKDO_DMA) += oryukdo_dma.o\n',
 'drivers/dma/Kconfig':'\nconfig ORYUKDO_DMA\n\tbool "ORYUKDO copy/fill DMA"\n\tdepends on RISCV\n\tselect DMA_ENGINE\n\tselect DMA_VIRTUAL_CHANNELS\n',
}
# Save independent copies before removing the exact known append from its target.
restored=[]
for name,suffix in suffixes.items():
 p=root/name
 if p.is_symlink():
  assert p.resolve()==base/name
  data=p.read_bytes();assert data.endswith(suffix.encode())
  p.unlink();p.write_bytes(data)
  (base/name).write_bytes(data[:-len(suffix.encode())])
  restored.append(name)
count=0
for p in root.rglob('*'):
 if p.is_symlink():
  target=p.resolve()
  if target.is_relative_to(root): continue
  if p.is_dir():
   p.unlink();shutil.copytree(target,p,symlinks=False)
  else:
   assert p.is_file(),p
   p.unlink();shutil.copy2(target,p)
  count+=1
print(json.dumps({'materialized_links':count,'restored_original_hooks':restored}))
