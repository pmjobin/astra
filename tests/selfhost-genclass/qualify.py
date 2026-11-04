#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run scoped GENCLASS gates; never infer acceptance from a child exit alone."""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
C0_SHA = 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('compiler', 'component', 'historical', 'selection', 'supplemental', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--gate', choices=('new', 'inherited', 'Class', 'mutations', 'negative', 'focused', 'continuity', 'layout', 'failure', 'retirement'), required=True)
	a = p.parse_args()
	assert sha(a.compiler) == C0_SHA
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	assert ['-'+a.mode] == [value for value in identity['identity']['argv'] if value in ('-O0', '-O2')]
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	commands, receipts = [], []
	def run(argv, name, expected=0):
		start = time.monotonic()
		with (a.runtime/(name+'.stdout')).open('xb') as out, (a.runtime/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=ROOT, stdout=out, stderr=err, timeout=1800)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stdout_sha256=sha(a.runtime/(name+'.stdout')), stderr_sha256=sha(a.runtime/(name+'.stderr'))))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(name, r.returncode, flush=True); assert r.returncode == expected, str(a.runtime/(name+'.stderr'))
		return commands[-1]
	def child(script, name, args):
		run([sys.executable, '-B', ROOT/script, *args], name)
	def result(path):
		data = read(path); assert data['status'] == 'PASS', str(path)
		receipts.append(dict(path=str(path), sha256=sha(path))); return data
	common = ['--component', a.component, '--compiler', a.compiler, '--compiler-sha256', C0_SHA, '--mode', a.mode]
	leaf = a.runtime/'observations'; output = a.build/'products'
	paths = ['--build', output, '--runtime', leaf]
	old_manifest = read(a.historical/('native-corpus-v4-'+a.mode)/'manifest.json')
	selections = list(old_manifest['selections'])
	assert all(sha(path) == value for path, value in old_manifest['selections'].items())
	select_args = [arg for path in selections for arg in ('--selection', path)]
	if a.gate == 'new':
		items = [row for row in read(a.selection) if row['name'] != 'class-nested-owner'] + [row for row in read(a.supplemental) if row['name'] != 'combined-mutations']
		assert len(items) >= 12 and len({tuple(x['sha256'] for x in row['sources']) for row in items}) == len(items)
		child('tests/selfhost-classstorage/run.py', 'new-native', [*common, *paths, '--selection', a.selection, '--selection', a.supplemental, *[arg for row in items for arg in ('--case', row['name'])]])
		rows = read(leaf/'results.json'); assert len(rows) == len(items) and all(row['baseline_complete'] for row in rows)
		for row in items:
			name = row['name']+'-independent-source'
			run([a.component, '--classstorage-genclass-consumer', a.mode, output/'unused', *[source['path'] for source in row['sources']]], name)
			assert (a.runtime/(name+'.stdout')).read_bytes().endswith(b'GENCLASS_SOURCE_CONSUMER_VALID\n')
		deferred = next(row for row in read(a.supplemental) if row['name'] == 'combined-mutations')
		sources = [source['path'] for source in deferred['sources']]
		for stage in ('genclass-consumer', 'core', 'cfg'):
			run([a.component, '--classstorage-'+stage, a.mode, output/'unused', *sources], 'bounded-three-specializations-'+stage)
		run([a.component, '--classstorage-ssa', a.mode, output/'unused', *sources], 'bounded-three-specializations-ssa', 2)
		assert b'native ABI SSA 2 2' in (a.runtime/'bounded-three-specializations-ssa.stderr').read_bytes()
		destination = output/'resource-refusal.o'; destination.write_bytes(b'preserved resource refusal destination\n'); original = sha(destination)
		run([a.component, '--classstorage-emit-obj', a.mode, destination, *sources], 'bounded-three-specializations-writer', 2)
		assert sha(destination) == original
		receipts.append(dict(name=deferred['name'], classification='C0_ADMITTED_SSA_RESOURCE_DEFERRED', sources=deferred['sources'], unchanged_work_limit=8000000, destination_preserved=original))
		receipts.append(dict(path=str(leaf/'results.json'), sha256=sha(leaf/'results.json'), distinct_new=len(rows)))
	elif a.gate == 'inherited':
		old = read(a.historical/('inherited-native-v4-'+a.mode)/'commands.json')
		frozen = [row['argv'][row['argv'].index('--frozen')+1] for row in old]
		child('tools/qualification/llvm23-native-replay.py', 'inherited-native', [*common, *paths, '--legacy', frozen[0], '--additional', frozen[1], '--generics', frozen[2]])
		data = result(leaf/'result.json'); assert len(data['profiles'][a.mode]) == 52
	elif a.gate == 'Class':
		old = read(a.historical/('native-corpus-v4-'+a.mode)/'results.json'); assert len(old) == 23
		child('tests/selfhost-classstorage/run.py', 'Class-native', [*common, *paths, *select_args, *[arg for row in old for arg in ('--case', row['name'])]])
		rows = read(leaf/'results.json'); assert len(rows) == 23 and all(row['baseline_complete'] for row in rows)
		assert [(row['name'], row['sources']) for row in rows] == [(row['name'], row['sources']) for row in old]
		receipts.append(dict(path=str(leaf/'results.json'), sha256=sha(leaf/'results.json'), frozen_Class=19, late_observers=4))
	elif a.gate == 'mutations':
		child('tests/selfhost-genclass/mutations.py', 'new-mutations', ['--component', a.component, '--mode', a.mode, *paths, '--selection', a.selection])
		assert result(leaf/'result.json')['distinct_categories'] >= 20
		manifest = read(a.historical/('mutations-v4-'+a.mode)/'manifest.json')
		old_leaf = a.runtime/'old-observations'
		child('tests/selfhost-classstorage/mutations.py', 'Class-mutations', ['--component', a.component, '--mode', a.mode, '--build', a.build/'old-products', '--runtime', old_leaf, *select_args, *[arg for row in manifest['cases'] for arg in ('--case', row['name'])]])
		data = result(old_leaf/'result.json'); assert data['distinct_model_categories'] == 17 and data['distinct_physical_categories'] == 18
	elif a.gate == 'negative':
		child('tests/selfhost-genclass/negative.py', 'new-negatives', ['--component', a.component, '--compiler', a.compiler, '--mode', a.mode, *paths])
		assert len(result(leaf/'result.json')['cases']) == 14
		child('tests/selfhost-classstorage/negative.py', 'Class-negatives', [*common, '--build', a.build/'old-products', '--runtime', a.runtime/'old-observations'])
		result(a.runtime/'old-observations/result.json')
	elif a.gate == 'focused':
		old = a.historical/'inherited-focused-v4/commands.json'
		for row in read(old):
			if not row['name'].endswith(a.mode): continue
			argv = row['argv'].copy(); name = row['name']
			for flag, value in (('--component', a.component), ('--build', a.build/name), ('--runtime', a.runtime/name)):
				if flag in argv: argv[argv.index(flag)+1] = str(value)
				# Frozen numeric/lifetime/boundary inputs remain exact historical bytes.
			run(argv, name); result(a.runtime/name/'result.json')
		receipts.append(dict(path=str(old), sha256=sha(old), role='exact inherited command selection'))
	elif a.gate == 'continuity':
		old = a.historical/('source-continuity-v4-'+a.mode)
		frozen = a.historical.parents[1]/'ssa11/frozen'
		child('tests/selfhost-ssa/run.py', 'source-continuity', ['--build', a.component.parent, '--product-prefix', a.component.name[:-2], '--frozen', frozen, '--mode', a.mode, '--runtime', leaf])
		data = result(leaf/'result.json'); assert data['outcomes'] == read(old/'result.json')['outcomes']
		prior, current = read(old/'commands.json'), read(leaf/'commands.json'); assert len(prior) == len(current)
		assert all((left['argv'][1:], left['exit'], left['stdout_sha256']) == (right['argv'][1:], right['exit'], right['stdout_sha256']) for left, right in zip(prior, current))
		receipts.append(dict(original_80_statuses=data['outcomes'], exact_replayed_commands=len(prior), Core=22, CFG=26, SSA=30))
	elif a.gate == 'layout':
		child('tests/selfhost-classstorage/layout-lifetime.py', 'layout-lifetime', ['--component', a.component, '--mode', a.mode, *paths, '--selection', a.selection, '--case', 'class-initial-reserve'])
		result(leaf/'result.json')
	elif a.gate == 'failure':
		child('tests/selfhost-classstorage/failure.py', 'constructor-failure', ['--baseline', a.runtime.parent/('new-'+a.mode)/'observations/results.json', '--compiler', a.compiler, '--compiler-sha256', C0_SHA, *paths, '--case', 'constructor-failure'])
		assert read(leaf/'result.json')['status'] == 'MATCHED_C0_FATAL_ALLOCATION_POLICY'
		receipts.append(dict(path=str(leaf/'result.json'), sha256=sha(leaf/'result.json'), normal_exit_memory_clean_claim=False))
	elif a.gate == 'retirement':
		child('tests/selfhost-genclass/retirement.py', 'retirement', ['--baseline', a.runtime.parent/('new-'+a.mode)/'observations/results.json', '--compiler', a.compiler, *paths])
		result(leaf/'result.json')
	assert sha(a.component) == identity['sha256']
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', gate=a.gate, mode=a.mode, component_sha256=sha(a.component), component_identity_sha256=sha(a.component.with_suffix('.identity.json')), recipe_sha256=sha(__file__), receipts=receipts, limitation='This receipt qualifies only its named gate; publication requires every gate and source/preservation evidence.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
