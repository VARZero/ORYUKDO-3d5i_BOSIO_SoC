"""Reject local edits to both preserved board-example and selected official IP."""
from pathlib import Path
import hashlib, json

def verify():
    here=Path(__file__).resolve().parent
    original=here/'vendor/hdmi'
    checked=0
    for name,expected in json.loads((original/'original_sha256.json').read_text()).items():
        assert hashlib.sha256((original/name).read_bytes()).hexdigest()==expected, name
        checked+=1
    selected=here/'vendor/digilent_rgb2dvi'
    manifest=json.loads((selected/'upstream_sources.json').read_text())
    for item in manifest['files']:
        assert hashlib.sha256((selected/item['file']).read_bytes()).hexdigest()==item['sha256'], item['file']
        checked+=1
    return checked,manifest['commit']

if __name__=='__main__':
    count,commit=verify()
    print(f'PASS VENDOR_SOURCE_INTEGRITY files={count} official_commit={commit}')
