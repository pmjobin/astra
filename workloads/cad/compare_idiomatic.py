#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact original native coverage plus the original 39-report JSON policy."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

sys.dont_write_bytecode = True
from compare import compare, native_artifacts

TIMING = {'Analytical/results.json': 'seconds', 'Synthetic/results.json': 'seconds', 'Differential/results.json': 'seconds', 'CorrectionImages/results.json': 'seconds', 'CorrectionImages/locality-invariants.json': 'runtime', 'CorrectionImages/orientation-images.json': 'runtime'}
TIMING.update({'References/' + name + '.json': 'seconds' for name in ['natural', 'cartoon', 'pixel-art', 'near-cardinal']})


def identity(path, root):
	parts = list(path.relative_to(root).parts)
	for index, part in enumerate(parts):
		if part.isdecimal() and index and parts[index - 1].endswith('-state'):
			parts[index] = '{run}'
	return '/'.join(parts)


def differences(left, right, path=''):
	if type(left) != type(right):
		return [path + '/{type}']
	if isinstance(left, dict):
		if left.keys() != right.keys():
			return [path + '/{keys}']
		return [item for key in left for item in differences(left[key], right[key], path + '/' + key)]
	if isinstance(left, list):
		if len(left) != len(right):
			return [path + '/{length}']
		return [item for index, (a, b) in enumerate(zip(left, right)) for item in differences(a, b, path + '/' + str(index))]
	if isinstance(left, float):
		return [] if struct.pack('>d', left) == struct.pack('>d', right) else [path]
	return [] if left == right else [path]


def qualify(left, right, output):
	output.mkdir(parents=True, exist_ok=False)
	record = compare(left, right)
	(output / 'native.json').write_text(json.dumps(record, indent='\t') + '\n')
	assert record['status'] == 'EXACT_RETAINED_ARTIFACTS' and len(record['rows']) == 20560, record['first_difference_in_sorted_artifact_order']
	selected = [set(native_artifacts(root).values()) for root in [left, right]]
	maps = [{identity(path, root): path for path in root.rglob('*.json') if path not in excluded} for root, excluded in zip([left, right], selected)]
	assert maps[0].keys() == maps[1].keys() and len(maps[0]) == 39
	rows = []
	for name, a in sorted(maps[0].items()):
		b = maps[1][name]
		x, y = json.loads(a.read_text()), json.loads(b.read_text())
		changed = differences(x, y)
		field = TIMING.get(name)
		allowed = ['/' + field] if field and isinstance(x, dict) else ['/' + str(index) + '/' + field for index in range(len(x))] if field else []
		row = {'identity': name, 'different_fields': changed, 'allowed_fields': allowed, 'bytes_equal': a.read_bytes() == b.read_bytes(), 'left_sha256': hashlib.sha256(a.read_bytes()).hexdigest(), 'right_sha256': hashlib.sha256(b.read_bytes()).hexdigest()}
		rows.append(row)
		(output / 'other-json.json').write_text(json.dumps(rows, indent='\t') + '\n')
		assert set(changed) <= set(allowed), row
	result = {'status': 'EXACT_ORIGINAL_OBSERVATIONS', 'native_artifacts': len(record['rows']), 'other_JSON_reports': len(rows), 'byte_identical_JSON': sum(row['bytes_equal'] for row in rows), 'timing_only_JSON': sum(bool(row['different_fields']) for row in rows), 'policy': 'Exact native bytes; other JSON uses exact decoded types and binary64 bits. Only the listed original timing fields and run-directory identities may differ. No payload rewriting, numeric tolerance or symmetry permutation.'}
	(output / 'result.json').write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps(result))


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('left', type=Path)
	parser.add_argument('right', type=Path)
	parser.add_argument('--output', type=Path, required=True)
	args = parser.parse_args()
	qualify(args.left.resolve(), args.right.resolve(), args.output.resolve())
