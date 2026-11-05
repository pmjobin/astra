#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run source-bound INDEXPATH gates and replay the exact predecessor closure."""
import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time
from state import ROOT, RUNTIME, PRIOR, sha, read

C0 = ROOT.parent/'codex/work/astra/build/llvm23-migration/production-final/astrac'
C0_SHA = 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('component', 'runtime', 'build'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--gate', choices=('new', 'mutations', 'negative', 'predecessor-text', 'predecessor-native'), required=True)
	a = p.parse_args(); assert sha(C0) == C0_SHA
	assert a.runtime.resolve().is_relative_to(RUNTIME) and a.build.resolve().is_relative_to(ROOT.parent/'codex/work/astra/build/indexpath18')
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	assert [flag for flag in identity['identity']['argv'] if flag in ('-O0', '-O2')] == ['-'+a.mode]
	commands = []; receipts = []
	def run(argv, name, expected=0):
		start = time.monotonic(); environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('VALGRIND_OPTS', None)
		with (a.runtime/(name+'.stdout')).open('xb') as out, (a.runtime/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time', '-v', '-o', a.runtime/(name+'.time'), *map(str, argv)], cwd=ROOT, stdout=out, stderr=err, timeout=1800, env=environment)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stdout_sha256=sha(a.runtime/(name+'.stdout')), stderr_sha256=sha(a.runtime/(name+'.stderr')))); (a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		if expected is not None: assert r.returncode == expected, (name, r.returncode, str(a.runtime/(name+'.stderr')))
		print(name, r.returncode, flush=True); return r.returncode
	selection = RUNTIME/'frozen-v2/selection.json'; supplemental = RUNTIME/'supplemental-v1/selection.json'; growth = RUNTIME/'supplemental-growth-v1/selection.json'; operation = RUNTIME/'operation-v1/selection.json'; items = [row for row in read(selection) if row['name'] != 'original-CfgWalk'] + read(supplemental) + read(growth) + read(operation)
	if a.gate == 'new':
		assert len(items) >= 12 and len({tuple(row['sha256'] for row in item['sources']) for item in items}) == len(items)
		leaf = a.runtime/'observations'
		run([sys.executable, '-B', ROOT/'tests/selfhost-classstorage/run.py', '--compiler', C0, '--compiler-sha256', C0_SHA, '--component', a.component, '--mode', a.mode, '--selection', selection, '--selection', supplemental, '--selection', growth, '--selection', operation, '--case', 'original-index-operation', *[arg for row in items if row['name'] != 'original-index-operation' for arg in ('--case', row['name'])], '--build', a.build/'products', '--runtime', leaf], 'new-native')
		rows = read(leaf/'results.json'); assert len(rows) == len(items) and all(row['baseline_complete'] for row in rows)
		for item in items:
			for stage in ('core', 'cfg'):
				run([a.component, '--classstorage-'+stage, a.mode, a.build/'unused', *[row['path'] for row in item['sources']]], item['name']+'-'+stage)
				assert (a.runtime/(item['name']+'-'+stage+'.stdout')).read_bytes().startswith(('astra-'+stage+'/1\n').encode())
		receipts.append(dict(path=str(leaf/'results.json'), sha256=sha(leaf/'results.json'), distinct=len(rows)))
	elif a.gate == 'mutations':
		item = next(row for row in items if row['name'] == 'two-owners'); sentinel = a.build/'preserved.o'
		run([a.component, '--classstorage-emit-obj', a.mode, sentinel, *[row['path'] for row in item['sources']]], 'valid-object')
		run(['readelf', '-h', sentinel], 'valid-ELF'); assert b'ELF64' in (a.runtime/'valid-ELF.stdout').read_bytes()
		good = a.build/'preserved-native'; run(['gcc', sentinel, '-o', good], 'valid-link'); run([good], 'valid-execute', item['expected_exit'])
		original = sha(sentinel); executable = sha(good)
		run([a.component, '--classstorage-indexpath-mutations', a.mode, sentinel, *[row['path'] for row in item['sources']]], 'mutations')
		text = (a.runtime/'mutations.stdout').read_text(); assert sha(good) == executable
		assert text.count('INDEXPATH_MODEL_MUTATION ') == 14 and text.count('INDEXPATH_PHYSICAL_MUTATION ') == 8 and text.count(' LLVM_VALID ') == 8 and sha(sentinel) == original
		for family, case, count in [('loan', 'store-loop', 2), ('substitution', 'generic-array-a', 1)]:
			control = next(row for row in items if row['name'] == case)
			run([a.component, '--classstorage-indexpath-'+family+'-mutations', a.mode, sentinel, *[row['path'] for row in control['sources']]], family)
			assert (a.runtime/(family+'.stdout')).read_text().count('INDEXPATH_MODEL_MUTATION ') == count and sha(sentinel) == original
		receipts.append(dict(distinct_categories=25, LLVM_valid_physical=8, destination_preserved=original, native_executable_preserved=executable, sources=item['sources']))
	elif a.gate == 'negative':
		cases = read(RUNTIME/'frozen-v2/negatives.json'); results = []
		for row in cases:
			assert sha(row['source']) == row['sha256']
			exit = run([a.component, '--classstorage-admit', a.mode, a.build/'unused', row['source']], row['name'], None)
			assert exit != 0, row['name']; results.append(dict(**row, native_status=exit, limitation='C0-admitted indexed-field writes remain native-DEFERRED; the other four inputs are independent C0 negatives.'))
		(a.runtime/'negative-results.json').write_text(json.dumps(results, indent=2)+'\n'); receipts.append(dict(path=str(a.runtime/'negative-results.json'), sha256=sha(a.runtime/'negative-results.json')))
		full = next(row for row in read(selection) if row['name'] == 'original-CfgWalk'); sources = [row['path'] for row in full['sources']]
		for stage in ('core', 'cfg'): run([a.component, '--classstorage-'+stage, a.mode, a.build/'unused', *sources], 'full-original-'+stage)
		run([a.component, '--classstorage-ssa', a.mode, a.build/'unused', *sources], 'full-original-ssa', 2)
		assert b'native ABI SSA 2 2' in (a.runtime/'full-original-ssa.stderr').read_bytes()
		receipts.append(dict(case='original-CfgWalk-complete-body', classification='C0_QUALIFIED_NATIVE_SSA_RESOURCE_DEFERRED', unchanged_SSA_budget=8000000, sources=full['sources']))
	else:
		group = 'qualification-v10' if a.gate == 'predecessor-text' else 'qualification-predecessor-v10'
		prior = PRIOR/(group+'-'+a.mode+'-driver.json')
		for row in read(prior):
			argv = row['argv'].copy()
			if '--reuse-mutations' in argv:
				at = argv.index('--reuse-mutations'); del argv[at:at+2]
			name = argv[argv.index('--gate')+1]+'-'+a.mode
			for flag, value in [('--component', a.component), ('--build', a.build/name), ('--runtime', a.runtime/name)]: argv[argv.index(flag)+1] = str(value)
			run(argv, name); data = read(a.runtime/name/'result.json'); assert data['status'] == 'PASS', (name, data)
			receipts.append(dict(path=str(a.runtime/name/'result.json'), sha256=sha(a.runtime/name/'result.json')))
	assert sha(a.component) == identity['sha256']
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', gate=a.gate, mode=a.mode, component_sha256=sha(a.component), component_identity_sha256=sha(a.component.with_suffix('.identity.json')), recipe_sha256=sha(__file__), receipts=receipts, limitation='Only this named executed gate is qualified. Full milestone status requires every acceptance gate, source identity and publication. Historical proofs remain historical.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
