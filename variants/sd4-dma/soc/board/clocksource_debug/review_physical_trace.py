"""Review only the new boot, excluding UART received before JTAG reconfiguration."""
import argparse
from collections import Counter
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re

p = argparse.ArgumentParser()
p.add_argument('trial', type=Path)
a = p.parse_args()
raw = (a.trial/'uart.bin').read_bytes()
text = raw.decode('utf-8', errors='replace').replace('\r', '')
starts = list(re.finditer(r'OpenSBI v[^\n]*', text))
assert starts, 'No new boot banner observed'
boot = text[starts[-1].start():]
# Timer interrupts can preempt the other SBI marker between any two characters.
# Keep their complete records, then remove only those exact records to rejoin
# the interrupted foreground marker. Preserve the raw UART as primary evidence.
timer_markers = re.findall(r'\[(T[01L])\]\n', boot)
foreground = re.sub(r'\[T[01L]\]\n', '', boot)
markers = Counter(timer_markers)
markers.update(re.findall(r'^\[(C[0-4]|N[01]|X[0-5])\]$', foreground, re.M))
state = json.loads((a.trial/'status.json').read_text())
returned = bool(re.search(r'initcall 0xc0158114 returned 0', boot))
result = {
    'reviewed_at': datetime.now().astimezone().isoformat(),
    'bit_sha256': state['bit_sha256'],
    'scope': 'Physical board with trace-v2 diagnostic kernel; UART before last OpenSBI banner excluded',
    'raw_uart_sha256': hashlib.sha256(raw).hexdigest(),
    'trace_v2_entry_observed': 'calling  0xc0158114' in boot,
    'markers': dict(markers), 'clocksource_return_observed': returned,
    'shell_prompt_observed': 'oryukdo# ' in boot,
    'shell_and_guest_memory_acceptance': state['status'] == 'PASS_PHYSICAL_UART_SHELL_AND_GUEST_MEMORY',
    'command_results': state.get('commands', []),
    'memtotal_kib': state.get('memtotal_kib'),
    'upper_memory_range': state.get('upper_memory_range'),
    'instrumentation_limit': 'Raw SBI markers add execution time; use for control-flow localization, not uninstrumented timing.'
}
if returned:
    assert all(markers[k] >= 1 for k in ['C0','C1','C2','N0','X0','X1','X2','X3','X4','X5','N1','C3','C4'])
(a.trial/'boot_uart.txt').write_text(boot, encoding='utf-8')
(a.trial/'foreground_uart.txt').write_text(foreground, encoding='utf-8')
(a.trial/'trace_review.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
print(json.dumps(result, indent=2))
