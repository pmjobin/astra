#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual allocation/retirement order against independent C0/C++ measurements."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
from state import ROOT, RUNTIME, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--qualification', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args()
	leaf = RUNTIME/('lifetime-'+a.version+'-'+a.mode); leaf.mkdir(exist_ok=False)
	spec = importlib.util.spec_from_file_location('allocation_trace', ROOT/'tests/selfhost-callplace/lifetime.py'); previous = importlib.util.module_from_spec(spec); spec.loader.exec_module(previous)
	rows = read(a.qualification/'results.json'); allocation_programs = []; nonallocating = []
	for row in rows:
		trace = a.qualification/(row['name']+'-memory-native.stderr')
		if re.search(r'^--\d+-- calloc\(', trace.read_text(), re.M):
			allocations, events = previous.allocations(trace); allocation_programs.append(dict(name=row['name'], allocations=allocations, events=events, trace_sha256=sha(trace), all_traced_native_allocations_retired=True))
		else: nonallocating.append(row['name'])
	assert len(allocation_programs) >= 12
	row = next(row for row in rows if row['name'] == 'nested-direct-record'); layout = (a.qualification/'nested-direct-record-ABI-probe.stdout').read_text()
	sizes = {}
	for name in ('Cabinet', 'Frame', 'Sample'):
		match = re.search(r'^LAYOUT '+name+r' (\d+) (\d+) (\d+)$', layout, re.M); assert match; sizes[name] = int(match[1])
	observed = next(row for row in allocation_programs if row['name'] == 'nested-direct-record')['allocations']; assert len(observed) == 3
	owner, backing, frame = observed; assert [row['bytes'] for row in observed] == [sizes['Cabinet'], 2*sizes['Sample'], sizes['Frame']]
	assert owner['allocated'] < backing['allocated'] < frame['allocated'] and backing['freed'] < owner['freed'] < frame['freed']
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, allocating_programs=allocation_programs, nonallocating_programs=nonallocating, nested_owner_witness=dict(independent_sizes=sizes, backing_count=2, allocation_ids=[row['id'] for row in observed], retirement_ids=[backing['id'], owner['id'], frame['id']], contract='Record backing retires before its containing Class, which retires before the enclosing moved owner. Equal byte sizes do not identify allocations; the trace addresses and source construction order do.'), recipe_sha256=sha(__file__), boundary='Fresh normal-return native allocation identities and independently measured C0/C++ sizes. Both C0 and native Valgrind qualifications are separately retained; equal allocation counts are not required.'), indent=2)+'\n'); print(a.mode, len(allocation_programs), 'material allocation and normal-retirement witnesses')


if __name__ == '__main__':
	main()
