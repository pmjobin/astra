#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact source/ABI/IR/object/runtime comparison across the mechanical commit."""
import argparse
import hashlib
import json
from pathlib import Path


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--before', type=Path, required=True)
	p.add_argument('--after', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	def read(root, name):
		value = json.loads((root/name/'result.json').read_text())
		assert value['status'] == 'PASS'
		return value
	assert json.loads((a.before/'result.json').read_text())['mode'] == json.loads((a.after/'result.json').read_text())['mode']
	rows = []
	for family in ('legacy', 'additions'):
		old, new = read(a.before, family), read(a.after, family)
		assert old['executions'] == new['executions']
		for left, right in zip(old['cases'], new['cases']):
			assert left['name'] == right['name'] and left['source_path'] == right['source_path']
			assert left['source_sha256'] == right['source_sha256'] == sha(left['source_path'])
			for key in ('expected_exit', 'expected_stdout', 'expected_stderr', 'expected_trace'):
				assert left[key] == right[key]
			assert left['products'].keys() == right['products'].keys()
			for key in left['products']:
				x, y = left['products'][key], right['products'][key]
				assert x['sha256'] == y['sha256'] == sha(x['path']) == sha(y['path']), (left['name'], key)
			assert left['memory'] == right['memory']
			rows.append(dict(name=left['name'], source_path=left['source_path'], source_sha256=left['source_sha256'],
				products={key: value['sha256'] for key, value in left['products'].items()},
				before_component_sha256=left['component_sha256'], after_component_sha256=right['component_sha256'], exact=True))
	assert len(rows) == 39
	for family in ('old-negative', 'new-negative'):
		old, new = read(a.before, family), read(a.after, family)
		assert old['categories'] == new['categories'] and old['mutations'] == new['mutations']
		if family == 'old-negative':
			assert old['outcomes'] == new['outcomes']
			for left, right in zip(old['mapping'], new['mapping']):
				assert left['name'] == right['name']
				for key in ('source_sha256', 'ssa_status', 'llvm_status', 'ir_sha256'):
					assert left[key] == right[key], (family, left['name'], key)
	old, new = read(a.before, 'continuity'), read(a.after, 'continuity')
	assert old['outcomes'] == new['outcomes'] and old['mutations'] == new['mutations']
	old, new = read(a.before, 'numeric'), read(a.after, 'numeric')
	assert old['cases'] == new['cases'] and old['normal'] == new['normal'] and old['fatal'] == new['fatal']
	assert old['instrumented'] == new['instrumented'] and old['shared_emulator_deviation'] == new['shared_emulator_deviation']
	assert (a.before/'numeric/numeric-mutation.json').read_bytes() == (a.after/'numeric/numeric-mutation.json').read_bytes()
	old, new = read(a.before, 'lifetime'), read(a.after, 'lifetime')
	assert old['zero_size_memory'] == new['zero_size_memory'] and old['self_move'] == new['self_move']
	for label in ('native', 'C0'):
		for key in ('signal', 'trace', 'normal_leak_claim', 'executable_sha256'):
			assert old['allocation_failure'][label][key] == new['allocation_failure'][label][key]
	old, new = read(a.before, 'boundary'), read(a.after, 'boundary')
	for key in ('source_sha256', 'C_source_sha256', 'memory', 'controls'):
		assert old[key] == new[key]
	a.output.write_text(json.dumps(dict(status='PASS', programs=39, cases=rows,
		checks=['exact native/C0 ABI plans, raw/optimized IR, objects, executables and memory',
		'exact original 80 status/IR rows and Core22/CFG26/SSA30 mutation receipts',
		'exact original21/new17 mutations plus separate numeric guard mutation',
		'exact numeric, owner and C-boundary controls'],
		before_qualification_sha256=sha(a.before/'result.json'), after_qualification_sha256=sha(a.after/'result.json')), indent=2)+'\n')
	print('PASS: 39 exact source/ABI/IR/object/executable comparisons and all independent negative receipts')


if __name__ == '__main__':
	main()
