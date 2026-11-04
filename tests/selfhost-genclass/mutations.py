#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Require real semantic and type-valid LLVM mutations with restored twins."""
import argparse
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
MODELS = ['wrong-element-nominal', 'erased-slot-type', 'lost-slot-ownership', 'cross-specialization-field-owner', 'rewired-source-field-map', 'erased-generic-payload-nominal', 'foreign-type-parameter-owner', 'cross-specialization-method-receiver', 'owning-hidden-receiver', 'erased-hidden-receiver-type', 'wrong-result-ownership', 'missing-source-constructor-argument', 'wrong-constructor-argument-type', 'forged-field-source-span', 'copied-Class-parameter']
PHYSICAL = {80:'lost-constructor-argument-value', 81:'wrong-method-specialization', 82:'pointer-stride-for-record-slots', 83:'wrong-record-shift-index', 84:'uncleared-record-tail', 85:'replace-keeps-old-record'}


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('component', 'selection', 'build', 'runtime'):
		p.add_argument('--'+name, required=True, type=Path)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	identity = json.loads(a.component.with_suffix('.identity.json').read_text()); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	items = [row for row in json.loads(a.selection.read_text()) if row['name'] in ('record-nominal-separation', 'class-replace')]; assert len(items) == 2
	commands, rows = [], []
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=a.build, capture_output=True, timeout=300)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start)); (a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == 0, (name, r.returncode, r.stderr[-1800:]); return r.stdout
	for item in items:
		assert all(sha(row['path']) == row['sha256'] for row in item['sources']); sources = [row['path'] for row in item['sources']]
		before = run([a.component, '--classstorage-ssa', a.mode, a.build/'unused', *sources], item['name']+'-valid-SSA')
		output = a.build/'forbidden.o'; output.write_bytes(b'preserved-genclass-mutation-destination\n'); original = sha(output)
		for family in (('model', 'native') if item['name'] == 'record-nominal-separation' else ('model',)):
			text = run([a.component, '--classstorage-genclass-'+family+'-mutations', a.mode, output, *sources], item['name']+'-'+family).decode(); seen = set()
			for line in text.splitlines():
				parts = line.split(); prefix = 'GENCLASS_'+family.upper()+'_MUTATION'
				if not parts or parts[0] != prefix: continue
				category, stage = map(int, parts[1:3]); assert category not in seen and 0 < stage < 5; seen.add(category)
				row = dict(case=item['name'], family=family, category=category, stage=stage, valid_restored=True)
				if family == 'model':
					assert category in range(len(MODELS)) and parts[3:] == ['VALID_RESTORED']; row['name'] = MODELS[category]
				else:
					assert category in PHYSICAL and parts[3] == 'LLVM_VALID'; valid, mutant, restored = map(bytes.fromhex, parts[4:]); assert valid != mutant and valid == restored
					row.update(name=PHYSICAL[category], LLVM_verifier_accepts_mutant=True, resealed=True, valid_sha256=hashlib.sha256(valid).hexdigest(), mutant_sha256=hashlib.sha256(mutant).hexdigest(), restored_sha256=hashlib.sha256(restored).hexdigest())
				rows.append(row)
			expected = set(PHYSICAL) if family == 'native' else set(range(14)) if item['name'] == 'record-nominal-separation' else {14}
			assert seen == expected, (family, seen)
			assert sha(output) == original
		after = run([a.component, '--classstorage-ssa', a.mode, a.build/'unused', *sources], item['name']+'-restored-SSA'); assert before == after
	assert {row['category'] for row in rows if row['family'] == 'model'} == set(range(15))
	assert all(sha(source['path']) == source['sha256'] for item in items for source in item['sources'])
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), selection_sha256=sha(a.selection), sources=[item['sources'] for item in items], distinct_categories=len(rows), observations=rows, preserved_destination_sha256=original, recipe_sha256=sha(__file__)), indent=2)+'\n')
	print(a.mode, len(rows), 'substantive categories rejected; all valid/restored twins accepted')


if __name__ == '__main__':
	main()
