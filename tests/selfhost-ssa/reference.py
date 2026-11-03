#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual C0 native execution and taken-path allocation/cleanup oracles."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import time

FLAGS = ['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible']
ORDER = {'ssa-argument-order': [8, 12], 'ssa-owning-return': [8, 8, 8, 8], 'ssa-borrow-end': [12]}


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'build', 'runtime', 'frozen'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	a.runtime.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=True)
	commands = []
	results = []
	compiler_hash = hashlib.sha256(a.compiler.read_bytes()).hexdigest()
	assert compiler_hash == json.loads((a.frozen/'tools.json').read_text())[str(a.compiler)]
	def run(argv, name, expected):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=60)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, expected, r.stderr.decode()[-1500:])
		return r
	for item in json.loads((a.frozen/'cases.json').read_text()):
		if item['core_status']:
			continue
		assert hashlib.sha256(Path(item['paths'][0]).read_bytes()).hexdigest() == item['sha256']
		fatal = item.get('fatal_signal', item.get('facts', {}).get('fatal_signal'))
		for mode in ('O0', 'O2'):
			name = item['name']+'-'+mode
			exe = a.build/name
			run([a.compiler, '-'+mode, *item['paths'], '-o', exe], name+'-compile', 0)
			r = run([exe], name+'-execute', item.get('exit', 0))
			assert not r.stdout and not r.stderr
			if fatal:
				assert 'Command terminated by signal '+str(fatal) in (a.runtime/(name+'-execute.time')).read_text()
			else:
				r = run([*FLAGS, *(['--trace-malloc=yes'] if item['name'] in ORDER else []), exe], name+'-memory', item.get('exit', 0))
				assert b'ERROR SUMMARY: 0 errors' in r.stderr and not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]', r.stderr)
				if item['name'] in ORDER:
					live = {}
					observed = []
					for event in re.finditer(rb'calloc\((\d+),\s*(\d+)\) = (0x[0-9A-Fa-f]+)|free\((0x[0-9A-Fa-f]+)\)', r.stderr):
						count, width, address, freed = event.groups()
						if address:
							assert address not in live
							live[address] = int(count)*int(width)
						elif int(freed, 16):
							observed.append(live.pop(freed))
					assert observed == ORDER[item['name']] and not live, (name, observed)
			results.append(dict(name=name, source_sha256=item['sha256'], compiler_sha256=compiler_hash, product_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(), exit=item.get('exit', 0), fatal_signal=fatal, cleanup_bytes=ORDER.get(item['name'])))
			(a.runtime/'result.json').write_text(json.dumps(results, indent=2)+'\n')
		print(item['name'], flush=True)


if __name__ == '__main__':
	main()
