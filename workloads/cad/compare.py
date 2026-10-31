#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare retained native CAD artifacts exactly, without numeric tolerances."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys


def digest(path):
	with path.open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def native_artifacts(root):
	result = {}
	for path in sorted(root.rglob('*')):
		if not path.is_file():
			continue
		name = path.name
		if not (path.suffix in {'.csv', '.png'} or (name.startswith('stats-') and path.suffix == '.json') or name.endswith('-stats.jsonl') or (name.startswith('corrections-') and path.suffix == '.jsonl')):
			continue
		parts = list(path.relative_to(root).parts)
		# test_cad.execute creates exactly one time_ns directory in a fresh run.
		# Map that directory in the file identity only. File bytes are untouched.
		for i, part in enumerate(parts):
			if part.isdecimal() and i > 0 and parts[i - 1].endswith('-state'):
				parts[i] = '{run}'
		key = '/'.join(parts)
		if key in result:
			raise ValueError(f'ambiguous repeated output: {key}')
		result[key] = path
	return result


def first_difference(left, right):
	if left.suffix == '.csv':
		with left.open() as a, right.open() as b:
			for row, pair in enumerate(zip(a, b, strict=True), 1):
				if pair[0] != pair[1]:
					for column, fields in enumerate(zip(pair[0].strip().split(','), pair[1].strip().split(','), strict=True), 1):
						if fields[0] != fields[1]:
							return {'row': row, 'column': column, 'left': fields[0], 'right': fields[1], 'left_f64_bits': struct.pack('>d', float(fields[0])).hex(), 'right_f64_bits': struct.pack('>d', float(fields[1])).hex()}
	return {'kind': 'byte difference', 'left': str(left), 'right': str(right)}


def compare(left, right):
	a = native_artifacts(left)
	b = native_artifacts(right)
	rows = []
	missing = {'left_only': sorted(set(a) - set(b)), 'right_only': sorted(set(b) - set(a))}
	first = None
	for name in sorted(set(a) & set(b)):
		x = digest(a[name])
		y = digest(b[name])
		rows.append({'identity': name, 'left_path': str(a[name]), 'right_path': str(b[name]), 'left_sha256': x, 'right_sha256': y, 'equal': x == y})
		if x != y and first is None:
			first = dict(identity=name, **first_difference(a[name], b[name]))
	matched = bool(rows) and not any(missing.values()) and first is None
	return {'status': 'EXACT_RETAINED_ARTIFACTS' if matched else 'FAIL_CORRECTNESS', 'scope': 'Only the listed retained native artifacts; does not certify complete corpus or application qualification.', 'rows': rows, 'missing': missing, 'first_difference_in_sorted_artifact_order': first}


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('left', type=Path)
	parser.add_argument('right', type=Path)
	parser.add_argument('--output', type=Path, required=True)
	args = parser.parse_args()
	record = compare(args.left.resolve(), args.right.resolve())
	args.output.write_text(json.dumps(record, indent='\t') + '\n')
	print(json.dumps({k: v for k, v in record.items() if k != 'rows'}, indent='\t'))
	print(f'{len(record["rows"])} retained artifacts compared')
	return 0 if record['status'] == 'EXACT_RETAINED_ARTIFACTS' else 1


if __name__ == '__main__':
	sys.exit(main())
