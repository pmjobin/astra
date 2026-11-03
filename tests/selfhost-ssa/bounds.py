#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact SSA arena/output/work boundaries; upstream depth is separately labelled."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time


def main():
	p = argparse.ArgumentParser()
	for key in ('build', 'runtime', 'frozen'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', action='append')
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	items = {x['name']: x for x in json.loads((a.frozen/'cases.json').read_text())}
	commands = []
	results = []
	def run(argv, name, expected):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], capture_output=True, timeout=60)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		if expected is not None:
			assert r.returncode == expected, (name, r.returncode, r.stderr.decode()[-1500:])
		if r.returncode:
			assert not r.stdout
		return r
	wide = a.runtime/'wide.astra'
	wide.write_text('int main(){int x=0;'+'x=x+1;'*260+'return x-260;}\n')
	deep = a.runtime/'depth.astra'
	deep.write_text('int main(){return '+'('*200+'0'+')'*200+';}\n')
	loop = a.runtime/'infinite.astra'
	loop.write_text('int main(){while(true){continue;}return 0;}\n')
	for mode in a.mode or ('O0', 'O2'):
		exe = a.build/('astra-ssa-'+mode)
		case = items['ssa-counter']['paths']
		baseline = run([exe, '--ssa', *case], 'control-'+mode, 0).stdout
		for limit, expected in [(len(baseline), 0), (len(baseline)-1, 2), (0, 2), (16777217, 2), ('-1', 2), ('x', 2), ('2147483648', 2), ('99999999999999999999', 2)]:
			r = run([exe, '--ssa-output-limit', str(limit), *case], 'output-'+str(limit)+'-'+mode, expected)
			if not expected:
				assert r.stdout == baseline
			else:
				assert r.stderr.startswith(b'SSA_RESOURCE_EXHAUSTED')
		meta = next(x for x in baseline.splitlines() if x.startswith(b'SSA_META '))
		minimum = max(map(int, meta.split()[1:9]))
		for limit, expected in [(minimum, 0), (minimum-1, 2), (0, 2), (65537, 2), ('2147483648', 2), ('x', 2)]:
			run([exe, '--ssa-limit', str(limit), *case], 'arena-'+str(limit)+'-'+mode, expected)
		low, high = 1, 8000000
		while low < high:
			middle = (low+high)//2
			r = run([exe, '--ssa-work-limit', str(middle), *case], 'work-'+str(middle)+'-'+mode, None)
			assert r.returncode in (0, 2)
			if r.returncode:
				assert r.stderr.startswith(b'SSA_RESOURCE_EXHAUSTED')
				low = middle+1
			else:
				high = middle
		run([exe, '--ssa-work-limit', str(low), *case], 'work-exact-'+mode, 0)
		run([exe, '--ssa-work-limit', str(low-1), *case], 'work-below-'+mode, 2)
		for limit in ('0', '8000001', '2147483648', 'x'):
			run([exe, '--ssa-work-limit', limit, *case], 'bad-work-'+limit+'-'+mode, 2)
		for case_name in ('unknown-call', 'bad-field'):
			r = run([exe, '--ssa-forge-input', *items[case_name]['paths']], 'forged-'+case_name+'-'+mode, 0)
			assert r.stdout == b'SSA_FORGED_INPUT_REJECTED\n'
			# Positive retained CFG and an SSA-specific graph/memory cap.
		cfg = run([exe, '--cfg', wide], 'wide-CFG-'+mode, 0).stdout
		assert sum(x.startswith(b'BLOCK ') for x in cfg.splitlines()) > 1024
		r = run([exe, '--ssa', wide], 'wide-SSA-'+mode, 2)
		assert r.stderr.startswith(b'SSA_RESOURCE_EXHAUSTED')
		# An inherited checked-input failure earns no SSA mutation/bound credit.
		r = run([exe, '--ssa', deep], 'upstream-depth-'+mode, 4)
		assert r.stderr.startswith(b'INVALID_VERIFIED_CFG')
		run([exe, '--ssa-walk', loop], 'finite-walk-infinite-source-'+mode, 0)
		results.append(dict(mode=mode, exact_arena_limit=minimum, exact_work_limit=low, exact_output_bytes=len(baseline), upstream_depth_status=4))
	(a.runtime/'sources.json').write_text(json.dumps({str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (wide, deep, loop)}, indent=2)+'\n')
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', boundaries=results, commands=len(commands)), indent=2)+'\n')


if __name__ == '__main__':
	main()
