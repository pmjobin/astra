#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""C0 allocation-order observations, independent of candidate CFG construction."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import time


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'build', 'runtime', 'frozen'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--historical-break', type=Path)
	p.add_argument('--core0', type=Path)
	p.add_argument('--core2', type=Path)
	a = p.parse_args()
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	a.runtime.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=True)
	commands = []
	def run(argv, name, expected):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr.decode()[-2000:])
		return r
	items = {x['name']: x for x in json.loads((a.frozen/'cases.json').read_text())}
	trace_results = []
	for mode in ('O0', 'O2'):
		item = items['ordered-owned-arguments']
		exe = a.build/('ordered-'+mode)
		run([a.compiler, '-'+mode, *item['paths'], '-o', exe], 'compile-'+mode, 0)
		r = run(['valgrind', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe], 'trace-'+mode, 0)
		assert b'ERROR SUMMARY: 0 errors' in r.stderr
		text = r.stderr.decode()
		allocations = {int(count)*int(width): address for count,width,address in re.findall(r'calloc\((2|3),\s*(4)\) = (0x[0-9A-Fa-f]+)', text)}
		assert allocations.keys() == {8, 12}, text
		freed = {size: text.index('free('+address+')') for size,address in allocations.items()}
		assert freed[8] < freed[12], (mode, freed)
		trace_results.append(dict(mode=mode, first_argument_buffer_bytes=8, second_argument_buffer_bytes=12, free_positions=freed, observed_order=[8, 12]))
	if a.historical_break:
		data = a.historical_break.read_bytes()
		assert hashlib.sha256(data).hexdigest() == 'c04d14c0e2ee738a15b848251cbbab331724811f9e7910cab87872faadd98c01'
		path = a.runtime/'coreir9-break-control.astra'; path.write_bytes(data)
		for stage in ('--check', '--dump-core', '--dump-cfg'):
			run([a.compiler, stage, path], 'break-'+stage[2:], 0)
		for mode, core in [('O0', a.core0), ('O2', a.core2)]:
			r = run([core, '--core', path], 'break-core-'+mode, 0)
			(a.frozen/('coreir9-break-control-core-'+mode+'.stdout')).write_bytes(r.stdout)
			exe = a.build/('break-'+mode)
			run([a.compiler, '-'+mode, path, '-o', exe], 'break-compile-'+mode, 0)
			run([exe], 'break-execute-'+mode, 0)
			run(['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', exe], 'break-memory-'+mode, 0)
		(a.frozen/'supplemental.json').write_text(json.dumps([dict(name='coreir9-break-control', paths=[str(path)], sha256=hashlib.sha256(data).hexdigest(), core_status=0, historical=True, facts=dict(loops=1, breaks=1, continues=1))], indent=2)+'\n')
	(a.runtime/'order.json').write_text(json.dumps(trace_results, indent=2)+'\n')


if __name__ == '__main__':
	main()
