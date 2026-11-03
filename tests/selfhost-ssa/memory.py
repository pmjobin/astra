#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unsuppressed construction, verifier, queries, mutants and retained lifetimes."""
import argparse
import json
from pathlib import Path
import re
import resource
import subprocess
import time
from reference import FLAGS


def main():
	p = argparse.ArgumentParser()
	for key in ('build', 'runtime', 'frozen'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', action='append')
	a = p.parse_args()
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	a.runtime.mkdir(parents=True, exist_ok=False)
	items = {x['name']: x for x in json.loads((a.frozen/'cases.json').read_text())}
	commands = []
	for mode in a.mode or ('O0', 'O2'):
		exe = a.build/('astra-ssa-'+mode)
		checks = [
			('nested-owner-leaves', ['--ssa'], 0),
			('ssa-counter', ['--ssa-walk'], 0),
			('ssa-and-skip', ['--mutate-ssa'], 0),
			('owner-loop-exits', ['--mutate-ssa'], 0),
			('ssa-borrow-end', ['--mutate-ssa'], 0),
			('ssa-separate-functions', ['--ssa-cross-owner'], 0),
			('ssa-diamond', ['--ssa-cross-owner'], 0),
			('existing-deep', ['--ssa-retain'], 0),
			('channel-overlap', ['--ssa'], 4),
			('unknown-call', ['--ssa'], 3),
			('channel-overlap', ['--ssa-forge-input'], 0),
			('unknown-call', ['--ssa-forge-input'], 0),
			('ssa-straight', ['--ssa-limit', '1'], 2),
			('ssa-straight', ['--ssa-work-limit', '1'], 2),
			('ssa-straight', ['--ssa-output-limit', '1'], 2),
			('short-fatal-and', ['--ssa'], 0),
			('ssa-straight', ['--ssa-graphs'], 0),
		]
		for index, (case, option, expected) in enumerate(checks):
			name = str(index)+'-'+case+'-'+mode
			argv = [*FLAGS, str(exe), *option, *items[case]['paths']]
			start = time.monotonic()
			r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *argv], capture_output=True, timeout=120)
			(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
			(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
			commands.append(dict(argv=argv, exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
			(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
			assert r.returncode == expected, (name, r.returncode, r.stderr.decode()[-2000:])
			assert b'ERROR SUMMARY: 0 errors' in r.stderr and not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]', r.stderr)
			if expected:
				assert not r.stdout
			print(name, 'PASS', flush=True)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', checks=len(commands), suppressions=False), indent=2)+'\n')


if __name__ == '__main__':
	main()
