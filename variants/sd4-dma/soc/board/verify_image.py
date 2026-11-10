"""Independently parse the raw release image and compare against the firmware files."""
from pathlib import Path
import hashlib
import json
import struct
import sys
import zlib

image_path = Path(sys.argv[1]).resolve()
fw = Path(sys.argv[2]).resolve()
dtb = Path(sys.argv[3]).resolve()
image = image_path.read_bytes()
manifest = json.loads((image_path.parent / "manifest.json").read_text())
def check(condition, message):
    if not condition:
        raise ValueError(message)

check(len(image)%512 == 0 and image[510:512] == b"\x55\xaa", "MBR signature/size")
check(image[450] == 0xda, "boot partition type")
first, size = struct.unpack_from("<II", image, 454)
check(first == 2048 and first+size == len(image)//512, "MBR range")
check(image[first*512:first*512+8] == b"ORYSD001", "magic")
pos = first+1
for i, source in enumerate([fw / "fw_jump.bin", fw / "Image", dtb]):
    count, checksum = struct.unpack_from("<II", image, first*512 + 8 + i*8)
    raw = source.read_bytes()
    payload = image[pos*512:(pos+count)*512]
    check(count == (len(raw)+511)//512 and len(payload) == count*512, source.name+" sectors")
    check(payload[:len(raw)] == raw and not any(payload[len(raw):]), source.name+" bytes/padding")
    check(zlib.crc32(payload) == checksum, source.name+" CRC32")
    entry = manifest["segments"][i]
    digest = hashlib.sha256(raw).hexdigest()
    check((entry["sha256"], entry["lba"], entry["sectors"]) == (digest, pos, count), "manifest")
    print(f"PASS {source.name} bytes={len(raw)} LBA={pos} sectors={count} sha256={digest}")
    pos += count
check(pos*512 == len(image), "trailing payload")
check(hashlib.sha256(image).hexdigest() == manifest["image_sha256"], "disk image hash")
print(f"PASS raw image bytes={len(image)} sha256={manifest['image_sha256']}")
