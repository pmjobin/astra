#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unsuppressed native component/consumer and normal C0 path checks."""
import argparse
import json
from pathlib import Path
import re
import resource
import subprocess
import time

FLAGS = ['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible']


def main():
	p = argparse.ArgumentParser()
	for key in ('build', 'runtime', 'frozen', 'reference'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	a.runtime.mkdir(parents=True, exist_ok=False)
	items = {x['name']: x for x in json.loads((a.frozen/'cases.json').read_text())}
	commands = []
	def run(argv, name, expected, memory=False):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], capture_output=True)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr.decode()[-3000:])
		if memory:
			assert b'ERROR SUMMARY: 0 errors' in r.stderr and not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]', r.stderr)
		return r
	for mode in ('O0', 'O2'):
		exe = a.build/('astra-cfg-'+mode)
		for case, command in [('nested-owner-leaves', '--cfg'), ('owner-loop-exits', '--cfg-walk'), ('short-skip', '--mutate-cfg'), ('nested-owner-leaves', '--mutate-cfg'), ('existing-deep', '--cfg-retain'), ('channel-overlap', '--cfg'), ('unknown-call', '--cfg')]:
			run([*FLAGS, exe, command, *items[case]['paths']], case+'-'+command[2:]+'-'+mode, items[case]['core_status'], True)
		case = items['existing-nested']
		run([*FLAGS, exe, '--cfg-cross-owner', *case['paths']], 'cross-'+mode, 0, True)
		for limit in ('0', '1', '3', '65537'):
			r = run([*FLAGS, exe, '--cfg-limit', limit, *case['paths']], 'limit-'+limit+'-'+mode, 2, True)
			assert not r.stdout and r.stderr.startswith(b'==') and b'CFG_RESOURCE_EXHAUSTED' in r.stderr
		for item in items.values():
			if 'facts' not in item or item['facts'].get('fatal_signal'): continue
			run([*FLAGS, a.reference/(item['name']+'-'+mode)], item['name']+'-C0-memory-'+mode, item['exit'], True)


if __name__ == '__main__':
	main()
