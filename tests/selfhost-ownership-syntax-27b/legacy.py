#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Requalify surviving exact 27-A legacy groups without expanding their scope."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil

from support import execute, output_path, sha, tool_identity, write

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
SELECTED = {'record-arrays', 'checked-record-results', 'caught-message-call', 'caught-message-scalars', 'owned-borrowed-calls', 'exit42', 'UTF8-multifile'}


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('compiler', 'c0', 'link', 'historical', 'build', 'runtime'): p.add_argument('--'+key, type=Path, required=True)
	for key in ('compiler', 'c0', 'historical'): p.add_argument('--'+key+'-sha256', required=True)
	a = p.parse_args()
	for key in ('compiler', 'c0', 'historical'):
		assert re.fullmatch('[0-9a-f]{64}', getattr(a, key+'_sha256')) and sha(getattr(a, key)) == getattr(a, key+'_sha256')
	runtime = output_path(a.runtime, WORK/'runtime'); build = output_path(a.build, WORK/'build')
	runtime.mkdir(parents=True, exist_ok=False); build.mkdir(parents=True, exist_ok=False)
	old = json.loads(a.historical.read_text()); assert len(old) == 13
	providers = {path:h for path, h in json.loads(a.link.read_text())['objects'].items() if Path(path).name not in ('llvm-capi.o', 'arguments.o')}
	assert len(providers) == 5 and all(sha(path) == h for path, h in providers.items())
	tools = tool_identity([a.compiler, a.c0, '/usr/bin/time', *[shutil.which(n) for n in ('cc', 'as', 'ld', 'valgrind', 'opt')]])
	inputs = {str(path):sha(path) for path in (Path(__file__), Path(__file__).with_name('support.py'), a.historical, a.link)}
	write(runtime/'identity.json', dict(inputs=inputs, tools=tools, providers=providers))
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	commands = []; programs = []
	def run(name, argv, expected=0):
		argv = list(map(str, argv)); r = execute(argv, runtime/name, expected=expected, timeout=600, env=env)
		commands.append(dict(name=name, argv=argv, result=r)); write(runtime/'commands.json', commands)
		assert r['status'] == 'EXPECTED_OUTCOME', (name, r)
		return ((runtime/name/'stdout').read_bytes(), (runtime/name/'stderr').read_bytes())
	def memory(name, argv, expected):
		run(name, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv], expected)
		log = (runtime/name/'stderr').read_bytes()
		assert all(v in log for v in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	for case in old:
		name = case['name']
		if name not in SELECTED: continue
		assert all(sha(path) == h for path, h in case['sources'].items())
		oracle = build/(name+'-C0'); links = [arg for path in providers for arg in ('--link-object', path)]
		run(name+'-C0-build', [a.c0, '-O0', *case['sources'], *links, '-o', oracle])
		expected = run(name+'-C0-native', [oracle], 42)
		raw = build/(name+'.ll'); memory(name+'-compiler-memory', [a.compiler, '--emit-llvm', '-o', raw, *case['sources']], 0)
		assert sha(raw) == case['raw_LLVM']['stage1'] == case['raw_LLVM']['stage2'], (name, sha(raw), case['raw_LLVM'])
		run(name+'-LLVM-verify', ['opt', '-passes=verify', '-disable-output', raw])
		products = {str(path):sha(path) for path in (oracle, raw)}
		for mode in ('O0', 'O2'):
			obj = build/(name+'-'+mode+'.o'); target = build/(name+'-'+mode)
			run(name+'-'+mode+'-compile', [a.compiler, '-c', '-'+mode, '-o', obj, *case['sources']])
			run(name+'-'+mode+'-link', ['cc', '-no-pie', obj, *providers, '-o', target])
			assert run(name+'-'+mode+'-native', [target], 42) == expected
			memory(name+'-'+mode+'-memory', [target], 42)
			products.update({str(path):sha(path) for path in (obj, target)})
		programs.append(dict(name=name, sources=case['sources'], raw_LLVM_identical=True, historical_raw_LLVM_sha256=sha(raw), products=products))
		write(runtime/'programs.json', programs); print(name, 'LEGACY_NATIVE_RAW_IDENTITY_MEMORY_PASS', flush=True)
	assert len(programs) == 7 and all(sha(path) == h for path, h in {**inputs, **tools, **providers}.items())
	for row in programs: assert all(sha(path) == h for path, h in {**row['sources'], **row['products']}.items())
	write(runtime/'result.json', dict(status='SELECTED_LEGACY_REGRESSIONS_PASS', compiler_sha256=a.compiler_sha256, historical_receipt_sha256=a.historical_sha256, programs=7, native_O0_O2_targets=14, strict_returning_memory_streams=21, identity_sha256=sha(runtime/'identity.json'), commands_sha256=sha(runtime/'commands.json'), programs_sha256=sha(runtime/'programs.json'), omitted_previous_groups=[row['name'] for row in old if row['name'] not in SELECTED], scope='Seven surviving byte-exact legacy groups have historical raw LLVM identities and fresh C0-oracle/native/memory checks. No complete 411-source or 101/52 mutation replay claim.'))


if __name__ == '__main__': main()
