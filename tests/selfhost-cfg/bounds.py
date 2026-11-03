#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real produced-model/output/work/depth limits and a nonterminating source loop."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import time


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'build', 'runtime', 'frozen'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', action='append')
	a = p.parse_args()
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	a.runtime.mkdir(parents=True, exist_ok=False)
	a.build.mkdir(parents=True, exist_ok=True)
	items = {x['name']:x for x in json.loads((a.frozen/'cases.json').read_text())}
	commands = []
	def run(argv, name, expected, timeout=120):
		start = time.monotonic()
		try:
			r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=timeout)
			status = r.returncode; stdout = r.stdout; stderr = r.stderr
		except subprocess.TimeoutExpired as error:
			status = 'TIMEOUT'; stdout = error.stdout or b''; stderr = error.stderr or b''
		(a.runtime/(name+'.stdout')).write_bytes(stdout); (a.runtime/(name+'.stderr')).write_bytes(stderr)
		commands.append(dict(argv=list(map(str, argv)), exit=status, monotonic_start=start, monotonic_end=time.monotonic(), timeout=timeout))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert status == expected, (name, status, expected, stderr.decode()[-2000:])
		return stdout, stderr
	work = a.runtime/'work.astra'; work.write_text('int main(){int n=0;'+'n=n+1;'*750+'return n-750;}\n')
	deep = a.runtime/'depth.astra'; deep.write_text('int main(){return '+'('*200+'0'+')'*200+';}\n')
	loop = a.runtime/'infinite.astra'; loop.write_text('int main(){while(true){continue;}return 0;}\n')
	for name,path in [('work', work), ('depth', deep), ('loop', loop)]:
		run([a.compiler, '--check', path], name+'-C0-check', 0)
	for mode in a.mode or ('O0', 'O2'):
		exe = a.build/('astra-cfg-'+mode)
		case = items['existing-nested']
		baseline, _ = run([exe, '--cfg', *case['paths']], 'output-control-'+mode, 0)
		for limit, expected in [(len(baseline), 0), (len(baseline)-1, 2), (1, 2), (0, 2), (16777217, 2), ('2147483648', 2), ('99999999999999999999999', 2), ('x', 2)]:
			out, err = run([exe, '--cfg-output-limit', str(limit), *case['paths']], 'output-'+str(limit)+'-'+mode, expected)
			if expected: assert not out and err.startswith(b'CFG_RESOURCE_EXHAUSTED')
			else: assert out == baseline
		for name in ('unknown-call', 'bad-field'):
			out, _ = run([exe, '--cfg-forge-input', *items[name]['paths']], 'forged-'+name+'-'+mode, 0)
			assert out == b'CFG_FORGED_INPUT_REJECTED\n'
			# A branch-rich graph has one more edge than blocks: isolate the edge
			# arena's exhaustion after the block and instruction arenas fit exactly.
		case = items['nested-loops']
		out, _ = run([exe, '--cfg', *case['paths']], 'edge-control-'+mode, 0)
		blocks = sum(x.startswith(b'BLOCK ') for x in out.splitlines())
		edges = sum(x.startswith(b'SUCC ') for x in out.splitlines())
		assert edges > blocks
		out, err = run([exe, '--cfg-limit', str(blocks), *case['paths']], 'edge-exhaustion-'+mode, 2)
		assert not out and err.startswith(b'CFG_RESOURCE_EXHAUSTED')
		run([exe, '--core', work], 'work-Core-'+mode, 0)
		out, err = run([exe, '--cfg', work], 'work-CFG-'+mode, 2)
		assert not out and err.startswith(b'CFG_RESOURCE_EXHAUSTED')
		# C0 accepts this syntax, but the inherited checked/admission depth
		# boundary rejects it. Keep that status distinct from CFG exhaustion.
		out, err = run([exe, '--cfg', deep], 'depth-'+mode, 4)
		assert not out and err.startswith(b'INVALID_VERIFIED_CORE')
		run([exe, '--cfg-walk', loop], 'infinite-walk-'+mode, 0, timeout=5)
		target = a.build/('infinite-reference-'+mode)
		run([a.compiler, '-'+mode, loop, '-o', target], 'infinite-compile-'+mode, 0)
		# This control intentionally never returns. It cannot qualify ordinary
		# unwinding or leaks. Run the executable directly so timeout kills it.
		start = time.monotonic()
		try:
			subprocess.run([target], capture_output=True, timeout=0.25)
			raise AssertionError('infinite C0 source returned')
		except subprocess.TimeoutExpired:
			commands.append(dict(argv=[str(target)], exit='EXPECTED_TIMEOUT', monotonic_start=start, monotonic_end=time.monotonic()))
			(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
	(a.runtime/'sources.json').write_text(json.dumps({str(x): hashlib.sha256(x.read_bytes()).hexdigest() for x in (work, deep, loop)}, indent=2)+'\n')


if __name__ == '__main__':
	main()
