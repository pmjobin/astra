#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reject source-owner and resealed physical forgeries with fresh valid twins."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
MODELS = [
	'foreign-source-owner', 'wrong-nominal-Class', 'by-value-Class',
	'wrong-handle-width', 'wrong-payload-extent', 'wrong-payload-alignment',
	'missing-initialized-field', 'wrong-field-parent', 'wrong-field-ordinal',
	'wrong-field-type', 'wrong-field-offset', 'erased-field-owner',
	'wrong-owner-slot-descriptor-width', 'wrong-record-stride',
	'wrong-field-symbol', 'wrong-pointer-alignment', 'extra-unreported-field',
]
PHYSICAL = {
	60: 'wrong-field-GEP-ordinal', 61: 'stale-cached-field-address', 63: 'handle-address-as-object',
	64: 'disabled-field-null-guard', 65: 'missing-constructor-call',
	66: 'wrong-constructor-borrowed-receiver', 67: 'short-object-allocation',
	68: 'omitted-owned-child-retirement', 69: 'duplicate-object-free',
	70: 'wrong-owner-slot-stride', 71: 'allocation-failure-reaches-transfer',
	72: 'missing-append-count', 73: 'uncleared-taken-owner-tail',
	74: 'replace-retires-incoming-owner', 75: 'missing-element-teardown',
	76: 'capacity-as-count', 77: 'detached-copy-of-owner-slots',
	78: 'unproved-slot-parameter-alignment',
}


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for name in ('component', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--selection', action='append', type=Path, required=True)
	p.add_argument('--case', action='append', required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	items = [item for path in a.selection for item in json.loads(path.read_text()) if item['name'] in a.case]
	assert len(items) == len(a.case) == len({item['name'] for item in items})
	manifest = dict(component_sha256=sha(a.component), mode=a.mode, selections={str(path):sha(path) for path in a.selection}, recipe_sha256=sha(__file__), cases=items, model_categories=MODELS, physical_categories=PHYSICAL)
	(a.runtime/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
	commands, rows = [], []
	def run(argv, name):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=a.build, capture_output=True, timeout=300, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == 0, (name, r.returncode, r.stderr[-1800:])
		return r.stdout.decode()
	for item in items:
		name = item['name']; sources = [Path(row['path']) for row in item['sources']]
		assert all(sha(row['path']) == row['sha256'] for row in item['sources'])
		before = run([a.component, '--classstorage-ssa', a.mode, a.build/'unused', *sources], name+'-before')
		out = a.build/(name+'-refused.o'); out.write_bytes(b'preserved-mutation-destination\n'); destination = sha(out)
		for family in ('model', 'native'):
			text = run([a.component, '--classstorage-'+family+'-mutations', a.mode, out, *sources], name+'-'+family)
			seen = set()
			for line in text.splitlines():
				parts = line.split()
				prefix = 'CLASS_STORAGE_'+('MODEL' if family == 'model' else 'NATIVE')+'_MUTATION'
				if not parts or parts[0] != prefix: continue
				category = int(parts[1]); assert category not in seen; seen.add(category)
				row = dict(case=name, family=family, category=category, fresh_valid_and_restored_controls=True, upstream_unchanged=True)
				if family == 'native':
					assert category in PHYSICAL and 0 < int(parts[2]) < 5
					old, mutant, restored = map(bytes.fromhex, parts[3:]); assert old != mutant and old == restored
					row.update(name=PHYSICAL[category], rejection_stage=int(parts[2]), before_sha256=hashlib.sha256(old).hexdigest(), mutant_sha256=hashlib.sha256(mutant).hexdigest(), restored_sha256=hashlib.sha256(restored).hexdigest(), resealed_mutant=True, writer_refused=True)
				else:
					assert 0 <= category < len(MODELS) and 'MUTANT' in parts and 'RESTORED' in parts
					row.update(name=MODELS[category], source_storage_consumer_refused=True)
				rows.append(row)
				(a.runtime/'observations.json').write_text(json.dumps(rows, indent=2)+'\n')
			assert seen, (name, family, 'no substantive mutation applied')
		assert sha(out) == destination
		after = run([a.component, '--classstorage-ssa', a.mode, a.build/'unused', *sources], name+'-after'); assert before == after
		print(name, 'independent mutations and valid/restored twins complete', flush=True)
	models = {row['category'] for row in rows if row['family'] == 'model'}
	physical = {row['category'] for row in rows if row['family'] == 'native'}
	assert models == set(range(len(MODELS))) and physical == set(PHYSICAL)
	assert len(models)+len(physical) >= 20 and sha(__file__) == manifest['recipe_sha256']
	assert all(sha(row['path']) == row['sha256'] for item in items for row in item['sources'])
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, distinct_model_categories=len(models), distinct_physical_categories=len(physical), observations=rows, limitation='This verifies mutated model/LLVM rejection and valid twins; runtime and inherited regression gates are separate.'), indent=2)+'\n')
	print(len(models), 'model and', len(physical), 'physical categories rejected at', a.mode)


if __name__ == '__main__':
	main()
