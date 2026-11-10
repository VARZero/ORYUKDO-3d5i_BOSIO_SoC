"""Build a raw MBR-partitioned boot card image from the board firmware."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import zlib

parser = argparse.ArgumentParser()
parser.add_argument("out", type=Path)
parser.add_argument("--firmware", type=Path, default=Path(__file__).resolve().parents[2] / "software/firmware")
args = parser.parse_args()
args.out.mkdir(parents=True, exist_ok=True)
dtb = args.out / "gen3.dtb"
subprocess.run(["dtc", "-I", "dts", "-O", "dtb", "-o", dtb, args.firmware / "gen3.dts"], check=True)
paths = [args.firmware / "fw_jump.bin", args.firmware / "Image", dtb]
limits = [8192, 251904, 2048]
bases = [0x80000000, 0x80400000, 0x87F00000]
header = bytearray(512)
header[:8] = b"ORYSD001"
payload = bytearray()
segments = []
for i, path in enumerate(paths):
    data = path.read_bytes()
    padded = data + bytes(-len(data) % 512)
    count = len(padded) // 512
    if not 0 < count <= limits[i]:
        raise ValueError(f"{path.name} exceeds its DDR region or is empty")
    crc = zlib.crc32(padded)
    struct.pack_into("<II", header, 8 + 8*i, count, crc)
    segments.append(dict(file=path.name, bytes=len(data), address=hex(bases[i]),
                         lba=2049 + len(payload)//512, sectors=count, crc32=f"{crc:08x}",
                         sha256=hashlib.sha256(data).hexdigest()))
    payload.extend(padded)
image = bytearray(2048*512)
# Non-filesystem partition, LBA fields authoritative; conventional sentinel CHS.
struct.pack_into("<B3sB3sII", image, 446, 0, bytes.fromhex("feffff"), 0xda,
                 bytes.fromhex("feffff"), 2048, 1+len(payload)//512)
image[510:512] = bytes.fromhex("55aa")
image.extend(header)
image.extend(payload)
target = args.out / "ORYUKDO-Gen3-BOSIO-KFB-1GiB-BusyBox.img"
target.write_bytes(image)
manifest = dict(image_sha256=hashlib.sha256(image).hexdigest(), image_bytes=len(image), segments=segments)
(args.out / "manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
print(json.dumps(manifest, indent=2))
