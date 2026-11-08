"""Accept a completed cold run; partial UART output must never count as PASS."""
from pathlib import Path
import argparse
import hashlib
import json
import re

p = argparse.ArgumentParser()
p.add_argument('log', type=Path)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
raw = a.log.read_text(encoding='utf-8', errors='replace')
assert not re.search(r'FAIL COLD_BOOT|%Error|Kernel panic', raw), 'Run failed'
assert re.search(r'^PASS SD_LOAD cold cycles=\d+ clear_lines=33554432 sectors=5531 ', raw, re.M), 'No full SD load'
match = re.search(r'^PASS COLD_SD_LINUX_SHELL cpu_cycles=(\d+) sd_cycles=(\d+) retires=(\d+) high_pages=(\d+) seconds=([\d.]+) first_pa=(0x[0-9a-f]+)$', raw, re.M)
assert match, 'Cold boot still incomplete: no SD-to-shell acceptance marker'
# Progress messages may occur between any two UART characters, including inside
# a printed address or prompt. Remove only the simulator's delimited records.
uart = re.sub(r'\[(?:CPU cycles=|SD cycles=|trap cause=)[^\]\n]*\]\n?', '', raw)
assert re.search(r'^42$', uart, re.M), 'Arithmetic response missing'
assert '6.12.0-oryukdo-kfb' in uart, 'Kernel-version response missing'
totals = re.findall(r'MemTotal:\s*(\d+)\s*kB', uart)
assert totals and all(900000 <= int(n) < 1048576 for n in totals), ('Unexpected RAM capacity', totals)
assert 'DDR_HIGH_OK pages=16' in uart, 'Guest upper-memory test missing'
guest_range = re.search(r'DDR_HIGH_OK pages=16 first_pa=(0x[0-9a-f]+) last_pa=(0x[0-9a-f]+)', uart)
assert guest_range, 'Guest pagemap physical range missing'
assert uart.count('oryukdo# ') >= 5, 'Shell command/return coverage incomplete'
cpu, sd, retires, pages = map(int, match.groups()[:4])
first_pa = int(match[6], 16)
assert pages >= 16 and 0x88000000 <= first_pa < 0xc0000000, 'Native upper-memory readback missing'
guest_lo, guest_hi = (int(value, 16) for value in guest_range.groups())
assert guest_lo == first_pa and guest_lo <= guest_hi < 0xc0000000, 'Guest PFN/native address mismatch'
# Progress samples bracket first shell arrival without changing or restarting
# the active simulation. Total completion cycles also include shell commands.
samples = [(int(c), int(stage)) for c, stage in re.findall(
    r'\[CPU cycles=(\d+) retires=\d+ pc=\S+ satp=\S+ stage=(\d+) seconds=', raw)]
shell_upper = next((c for c, stage in samples if stage > 0), cpu)
shell_lower = max((c for c, stage in samples if stage == 0 and c < shell_upper), default=0)
result = {
    'result': 'PASS', 'scope': 'Staged cold SD RTL to Linux UART BusyBox shell; modeled native DDR',
    'cpu_cycles': cpu, 'sd_ui_cycles': sd, 'retirement_event_cycles': retires,
    'native_high_pages_checked': pages, 'first_high_physical_address': hex(first_pa),
    'guest_high_physical_range': [hex(guest_lo), hex(guest_hi)],
    'memtotal_kib': list(map(int, totals)), 'wall_seconds': float(match[5]),
    'log_sha256': hashlib.sha256(a.log.read_bytes()).hexdigest(),
    'physical_board_tested': False, 'firmware_or_cpu_checkpoint_used': False,
    'first_shell_cpu_cycle_bracket': [shell_lower, shell_upper],
    'first_shell_model_clock_seconds_bracket': [sd / 100000000 + c / 50000000 for c in (shell_lower, shell_upper)],
    'boot_time_estimate_scope': 'Clock conversion at CPU 50MHz and SD UI 100MHz, retaining modeled response delays; excludes physical FPGA configuration, clock lock and DDR calibration. Actual card and DDR latency may differ.',
}
a.output.mkdir(parents=True, exist_ok=True)
(a.output / 'uart_transcript.txt').write_text(uart, encoding='utf-8')
(a.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print('PASS COLD_BOOT_RESULT_AUDIT', json.dumps(result))
