"""Compare cycle-stamped camera/projector/cache traces from +io_trace runs.

The assertions in tb_gen3_bosio additionally check the expected values; matching
simulators alone is not an architectural correctness proof.
"""
from pathlib import Path
from collections import Counter
from itertools import zip_longest
import argparse
import hashlib
import json

p = argparse.ArgumentParser()
p.add_argument('verilator', type=Path)
p.add_argument('xsim', type=Path)
p.add_argument('report', type=Path)
p.add_argument('--expect-difference', action='store_true')
args = p.parse_args()
counts = [Counter(), Counter()]
first = []
matched = total = 0
with args.verilator.open() as a, args.xsim.open() as b:
    for total, (left, right) in enumerate(zip_longest(a, b), 1):
        for index, line in enumerate((left, right)):
            if line: counts[index][line.split()[0]] += 1
        if left == right:
            matched += 1
        elif len(first) < 10:
            first.append({'line': total, 'verilator': left.strip() if left else None,
                          'xsim': right.strip() if right else None})
equal = total > 0 and matched == total
result = {'equal': equal, 'total_lines': total, 'matching_lines': matched,
          'stage_counts': list(counts), 'first_differences': first,
          'sha256': {str(f): hashlib.sha256(f.read_bytes()).hexdigest()
                     for f in (args.verilator, args.xsim)}}
args.report.parent.mkdir(parents=True, exist_ok=True)
args.report.write_text(json.dumps(result, indent=2)+'\n')
assert total and equal != args.expect_difference, 'Unexpected trace comparison result'
print(('EXPECTED DIFFERENCE' if args.expect_difference else 'PASS trace equivalence'),
      f'{matched}/{total} matching lines', args.report)
