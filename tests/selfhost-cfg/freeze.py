#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze fresh source/C0/Core identities before any candidate lowering exists."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import resource
import subprocess
import time
from corpus import cases

ROOT = Path(__file__).resolve().parents[2]


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'core', 'core2', 'runtime', 'build'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--core-prefix', default='astra-core-')
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	a.runtime.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=True)
	commands = []
	def run(argv, name):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], capture_output=True, cwd=a.build, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		return r
		# Existing maintained freezer preserves all 47 original admission outcomes.
	r = run(['python3', '-B', ROOT/'tests/selfhost-coreir/freeze.py', '--compiler', a.compiler, '--admission', a.core/(a.core_prefix+'O0'), '--runtime', a.runtime/'core'], 'core-freeze')
	assert r.returncode == 0, r.stderr
	items = []
	for group in ('frozen', 'additional-frozen'):
		items.extend(json.loads((a.runtime/'core'/group/'frozen.json').read_text()))
	for item in cases():
		leaf = a.runtime/item['name']
		leaf.mkdir()
		path = leaf/'input.astra'
		path.write_text(item['source']+'\n')
		item['paths'] = [str(path)]
		item['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
		item['core_status'] = 0
		items.append(item)
	for item in items:
		name = item['name']
		for stage in ('--check', '--dump-core', '--dump-cfg'):
			r = run([a.compiler, stage, *item['paths']], name+'-'+stage[2:])
			if item['core_status'] == 0: assert r.returncode == 0, (name, stage, r.stderr)
		for mode in ('O0', 'O2'):
			r = run([(a.core2 if mode == 'O2' else a.core)/(a.core_prefix+mode), '--core', *item['paths']], name+'-core-'+mode)
			assert r.returncode == item['core_status'], (name, mode, r.returncode, item['core_status'], r.stderr)
			if 'facts' in item:
				exe = a.build/(name+'-'+mode)
				assert run([a.compiler, '-'+mode, *item['paths'], '-o', exe], name+'-compile-'+mode).returncode == 0
				r = run([exe], name+'-execute-'+mode)
				assert r.returncode == item['exit'], (name, r.returncode, item['exit'])
				assert not r.stdout and not r.stderr
				if 'fatal_signal' in item['facts']:
					assert 'Command terminated by signal '+str(item['facts']['fatal_signal']) in (a.runtime/(name+'-execute-'+mode+'.time')).read_text()
		print(name, item['core_status'], flush=True)
	(a.runtime/'cases.json').write_text(json.dumps(items, indent=2)+'\n')
	(a.runtime/'tools.json').write_text(json.dumps({str(x): hashlib.sha256(x.read_bytes()).hexdigest() for x in (a.compiler, a.core/(a.core_prefix+'O0'), a.core2/(a.core_prefix+'O2'))}, indent=2)+'\n')


if __name__ == '__main__':
	main()
