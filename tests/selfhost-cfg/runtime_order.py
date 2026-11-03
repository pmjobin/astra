#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-authored C0 release-order expectations on actual taken exit paths."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

EXPECTED = {
	'ordered-owned-arguments': [8, 12],
	'owner-loop-exits': [12, 8] * 5,
	'owner-conditional-return': [12, 8] * 2,
	'nested-owner-leaves': [8, 4, 12, 8] * 2,
}


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'build', 'runtime', 'frozen'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=True)
	items = {x['name']:x for x in json.loads((a.frozen/'cases.json').read_text())}
	commands = []
	results = []
	compiler_hash = hashlib.sha256(a.compiler.read_bytes()).hexdigest()
	assert compiler_hash == json.loads((a.frozen/'tools.json').read_text())[str(a.compiler)]
	for name, expected in EXPECTED.items():
		item = items[name]
		assert hashlib.sha256(Path(item['paths'][0]).read_bytes()).hexdigest() == item['sha256']
		for mode in ('O0', 'O2'):
			exe = a.build/(name+'-'+mode)
			trace = b''
			for stage, argv in [('compile', [a.compiler, '-'+mode, *item['paths'], '-o', exe]), ('trace', ['valgrind', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe])]:
				start = time.monotonic()
				r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'-'+mode+'-'+stage+'.time')), *map(str, argv)], capture_output=True, cwd=a.build, env=dict(os.environ, CCACHE_DISABLE='1'))
				(a.runtime/(name+'-'+mode+'-'+stage+'.stdout')).write_bytes(r.stdout)
				(a.runtime/(name+'-'+mode+'-'+stage+'.stderr')).write_bytes(r.stderr)
				commands.append(dict(argv=list(map(str, argv)), source_sha256=item['sha256'], compiler_sha256=compiler_hash, exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
				(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
				assert r.returncode == 0 and not r.stdout, (name, mode, stage)
				if stage == 'trace': trace = r.stderr
			assert b'ERROR SUMMARY: 0 errors' in trace
			live = {}
			observed = []
			for event in re.finditer(rb'calloc\((\d+),\s*(\d+)\) = (0x[0-9A-Fa-f]+)|free\((0x[0-9A-Fa-f]+)\)', trace):
				count, width, address, freed = event.groups()
				if address:
					assert address not in live
					live[address] = int(count)*int(width)
				elif int(freed, 16):
					assert freed in live, (name, mode, freed)
					observed.append(live.pop(freed))
			assert observed == expected and not live, (name, mode, observed, expected, live)
			results.append(dict(name=name, mode=mode, expected_free_bytes=expected, observed_free_bytes=observed, product_sha256=hashlib.sha256(exe.read_bytes()).hexdigest(), source_sha256=item['sha256']))
	(a.runtime/'result.json').write_text(json.dumps(results, indent=2)+'\n')


if __name__ == '__main__':
	main()
