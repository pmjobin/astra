#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute focused TEXTCLASS gates with explicit source/product identities."""
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
	for name in ('compiler', 'component', 'frozen', 'supplemental', 'original', 'build', 'runtime'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--gate', choices=('new', 'mutations', 'negative', 'bounds', 'retirement', 'allocation', 'reserve', 'layout', 'adapter'), required=True)
	p.add_argument('--reuse-mutations', type=Path, help='Already executed current candidate mutation observations; exact identity checks remain mandatory')
	a = p.parse_args(); assert not a.reuse_mutations or a.gate == 'mutations'
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	assert sha(a.compiler) == C0_SHA
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	assert [arg for arg in identity['identity']['argv'] if arg in ('-O0', '-O2')] == ['-'+a.mode]
	commands, receipts = [], []
	def run(argv, name):
		start = time.monotonic()
		with (a.runtime/(name+'.stdout')).open('xb') as out, (a.runtime/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time', '-v', '-o', a.runtime/(name+'.time'), *map(str, argv)], cwd=ROOT, stdout=out, stderr=err, timeout=1800)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stdout_sha256=sha(a.runtime/(name+'.stdout')), stderr_sha256=sha(a.runtime/(name+'.stderr')))); (a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == 0, (name, str(a.runtime/(name+'.stderr')))
		print(name, 'completed; receipt validation follows', flush=True)
	def child(script, name, args):
		run([sys.executable, '-B', ROOT/script, *args], name)
	common = ['--compiler', a.compiler, '--component', a.component, '--mode', a.mode]
	leaf = a.runtime/'observations'; output = a.build/'products'; paths = ['--build', output, '--runtime', leaf]
	if a.gate == 'new':
		selections = [root/'selection.json' for root in (a.frozen, a.supplemental, a.original)]; items = [row for path in selections for row in read(path)]
		assert len(items) >= 16 and len({tuple(source['sha256'] for source in row['sources']) for row in items}) == len(items)
		child('tests/selfhost-classstorage/run.py', 'native', [*common, '--compiler-sha256', C0_SHA, *paths, *[arg for path in selections for arg in ('--selection', path)]])
		rows = read(leaf/'results.json'); assert len(rows) == len(items) and all(row['baseline_complete'] for row in rows)
		assert [(row['name'], row['sources']) for row in rows] == [(row['name'], row['sources']) for row in items]
		for name in ('original-Utf8Message', 'text-record-layout'):
			item = next(row for row in items if row['name'] == name)
			for stage in ('core', 'cfg'):
				run([a.component, '--classstorage-'+stage, a.mode, output/'unused', *[row['path'] for row in item['sources']]], name+'-'+stage)
				assert (a.runtime/(name+'-'+stage+'.stdout')).read_bytes().startswith(('astra-'+stage+'/1\n').encode())
		receipts.append(dict(path=str(leaf/'results.json'), sha256=sha(leaf/'results.json'), distinct_programs=len(rows)))
	elif a.gate == 'mutations':
		if a.reuse_mutations:
			leaf = a.reuse_mutations.resolve(); assert not leaf.is_relative_to(ROOT)
			data = read(leaf/'result.json')
			assert data['component_sha256'] == sha(a.component) and data['mode'] == a.mode and data['recipe_sha256'] == sha(ROOT/'tests/selfhost-textclass/mutations.py') and data['selection_sha256'] == sha(a.frozen/'selection.json')
			assert all(sha(row['path']) == row['sha256'] for row in data['sources']+data['release_sources'])
			assert all(row['exit'] == 0 for row in read(leaf/'commands.json'))
			assert (leaf/'model.stdout').read_text().count('TEXT_MODEL_MUTATION ') == 12 and (leaf/'native.stdout').read_text().count(' LLVM_VALID ') == 8 and (leaf/'release-models.stdout').read_text().count('TEXT_RELEASE_MUTATION ') == 4
			(a.runtime/'current-reuse.json').write_text(json.dumps(dict(classification='CURRENT_EXACT_PRODUCT_SOURCE_FLAGS_DEPENDENCIES_AND_RECIPE', observations=str(leaf), receipt_sha256=sha(leaf/'result.json'), reason='Fresh candidate observations already executed during the explicit-release pilot; no rerun or historical relabelling.'), indent=2)+'\n')
		else:
			child('tests/selfhost-textclass/mutations.py', 'text-mutations', ['--component', a.component, '--mode', a.mode, '--selection', a.frozen/'selection.json', *paths])
			data = read(leaf/'result.json')
		assert data['status'] == 'PASS' and data['distinct_categories'] == 24
		assert sum(row.get('LLVM_verifier_accepts_mutant', False) for row in data['observations']) == 8
		receipts.append(dict(path=str(leaf/'result.json'), sha256=sha(leaf/'result.json')))
	elif a.gate == 'negative':
		child('tests/selfhost-textclass/negative.py', 'text-negative', [*common, '--frozen', a.frozen, *paths])
		data = read(leaf/'result.json'); assert data['status'] == 'PASS' and len(data['cases']) == 7
		receipts.append(dict(path=str(leaf/'result.json'), sha256=sha(leaf/'result.json')))
	elif a.gate in ('retirement', 'allocation', 'reserve'):
		child('tests/selfhost-textclass/lifecycle.py', a.gate, ['--baseline', a.runtime.parent/('new-'+a.mode)/'observations/results.json', '--compiler', a.compiler, '--gate', a.gate, *paths])
		data = read(leaf/'result.json'); assert data['status'] == 'PASS'
		receipts.append(dict(path=str(leaf/'result.json'), sha256=sha(leaf/'result.json')))
	elif a.gate == 'bounds':
		child('tests/selfhost-textclass/bounds.py', 'text-bounds', [*common, '--frozen', a.frozen, *paths])
		data = read(leaf/'result.json'); assert data['status'] == 'PASS' and len(data['observations']) == 4
		receipts.append(dict(path=str(leaf/'result.json'), sha256=sha(leaf/'result.json')))
	elif a.gate == 'layout':
		child('tests/selfhost-classstorage/layout-lifetime.py', 'text-layout-lifetime', ['--component', a.component, '--mode', a.mode, '--selection', a.frozen/'selection.json', '--case', 'bag-replace', *paths])
		data = read(leaf/'result.json'); assert data['status'] == 'PASS' and data['valid_mutant_restored']
		receipts.append(dict(path=str(leaf/'result.json'), sha256=sha(leaf/'result.json')))
	elif a.gate == 'adapter':
		probe = ROOT/'tests/selfhost-textclass/literal-probe.c'; shim = a.component.parent/'llvm-capi.o'
		flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split(); libraries = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis', 'native'], text=True).split()
		assert read(shim.with_suffix('.identity.json'))['sha256'] == sha(shim)
		product = a.build/'literal-probe'; run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, probe, shim, *libraries, '-o', product], 'adapter-build'); run([product], 'adapter-execute')
		assert (a.runtime/'adapter-execute.stdout').read_bytes() == b'COUNTED_UTF8_NUL_EMPTY_AND_RESTORED_LITERAL_VALID\n'
		receipts.append(dict(source_sha256=sha(probe), shim_sha256=sha(shim), product_sha256=sha(product)))
	assert sha(a.component) == identity['sha256']
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', gate=a.gate, mode=a.mode, component_sha256=sha(a.component), component_identity_sha256=sha(a.component.with_suffix('.identity.json')), recipe_sha256=sha(__file__), receipts=receipts, limitation='Only this named gate is qualified. All preservation, predecessor, source-span, native, mutation and report gates are required for the scoped milestone; full compiler-source safety, exceptions/factory and Stage 1 remain separate.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
