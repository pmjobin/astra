#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Check text models, explicit release and LLVM-valid physical controls."""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
MODELS = ['erased-text-field-type', 'lost-readonly-snapshot', 'invented-explicit-owner-field', 'erased-property-result', 'unauthorized-setter', 'getter-wrong-receiver', 'erased-constructor-input', 'stale-getter-source-span', 'wrong-Flow-text-projection', 'lost-Flow-readonly-projection', 'wrong-text-field-offset', 'pointer-sized-text-descriptor']
PHYSICAL = {90:'zero-snapshot-copy-count', 91:'snapshot-copies-own-uninitialized-backing', 92:'truncated-snapshot-count', 93:'undersized-snapshot-allocation', 94:'incorrect-text-length-branch', 95:'zero-text-comparison-count', 96:'string-retirement-frees-Class', 97:'stored-dangling-borrow-instead-of-snapshot'}


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('component', 'selection', 'build', 'runtime'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	identity = json.loads(a.component.with_suffix('.identity.json').read_text()); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	item = next(row for row in json.loads(a.selection.read_text()) if row['name'] == 'bag-replace')
	assert all(sha(row['path']) == row['sha256'] for row in item['sources']); sources = [row['path'] for row in item['sources']]
	commands, observations = [], []
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', a.runtime/(name+'.time'), *map(str, argv)], cwd=a.build, capture_output=True, timeout=300)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start)); (a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == 0, (name, r.stderr[-1500:]); return r.stdout
	before = run([a.component, '--classstorage-ssa', a.mode, a.build/'unused', *sources], 'valid-SSA')
	output = a.build/'forbidden.o'; output.write_bytes(b'preserved-textclass-mutation-destination\n'); original = sha(output)
	for family in ('model', 'native'):
		data = run([a.component, '--classstorage-text-'+family+'-mutations', a.mode, output, *sources], family).decode(); seen = set()
		for line in data.splitlines():
			parts = line.split()
			if not parts or parts[0] != 'TEXT_'+family.upper()+'_MUTATION': continue
			category, stage = map(int, parts[1:3]); assert category not in seen and 0 < stage < 5; seen.add(category)
			row = dict(family=family, category=category, stage=stage, valid_restored=True)
			if family == 'model':
				assert parts[3:] == ['VALID_RESTORED']; row['name'] = MODELS[category]
			else:
				assert parts[3] == 'LLVM_VALID'; valid, mutant, restored = map(bytes.fromhex, parts[4:]); assert valid != mutant and valid == restored
				row.update(name=PHYSICAL[category], LLVM_verifier_accepts_mutant=True, resealed=True, valid_sha256=hashlib.sha256(valid).hexdigest(), mutant_sha256=hashlib.sha256(mutant).hexdigest(), restored_sha256=hashlib.sha256(restored).hexdigest())
			observations.append(row)
		assert seen == (set(range(12)) if family == 'model' else set(PHYSICAL))
		assert sha(output) == original
	after = run([a.component, '--classstorage-ssa', a.mode, a.build/'unused', *sources], 'restored-SSA'); assert before == after
	assert len(observations) == 20 and all(sha(row['path']) == row['sha256'] for row in item['sources'])
	release = next(row for row in json.loads(a.selection.read_text()) if row['name'] == 'independent-snapshot'); assert all(sha(row['path']) == row['sha256'] for row in release['sources'])
	data = run([a.component, '--classstorage-text-release-mutations', a.mode, output, *[row['path'] for row in release['sources']]], 'release-models').decode(); seen = set()
	names = ['wrong-release-owner-place', 'wrong-release-cleanup-owner', 'erased-release-obligation', 'CFG-release-uses-other-owner-contract']
	for line in data.splitlines():
		parts = line.split(); assert parts[0] == 'TEXT_RELEASE_MUTATION'; category, stage = map(int, parts[1:3]); assert category not in seen and 0 < stage < 5 and parts[3:] == ['VALID_RESTORED']; seen.add(category)
		observations.append(dict(family='release', category=100+category, name=names[category], stage=stage, valid_restored=True))
	assert seen == set(range(4)) and sha(output) == original
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), selection_sha256=sha(a.selection), sources=item['sources'], release_sources=release['sources'], distinct_categories=24, observations=observations, preserved_destination_sha256=original, recipe_sha256=sha(__file__)), indent=2)+'\n')
	print(a.mode, '12 text model, 4 explicit release and 8 LLVM-valid physical categories rejected, with accepted restored twins')


if __name__ == '__main__':
	main()
