# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Authored layout expectations and C0 logical-leaf correspondence."""
import re


def check(name, abi, c0_nabi):
	rows = [line.split() for line in abi.decode().splitlines()]
	types = {int(r[1]): tuple(map(int, r[2:])) for r in rows if r[0] == 'TYPE'}
	fields = [tuple(map(int, r[1:])) for r in rows if r[0] == 'FIELD']
	records = {n: r for n, r in types.items() if r[0] == 30}
	if name == 'record-identity':
		assert any(r == (30, 4, 4, 1) for r in records.values())
		assert b'(leaf #0 (field 0) I32)' in c0_nabi
	if name == 'record-nested':
		assert any(r == (30, 8, 8, 1) for r in records.values())
		roots = [n for n, r in records.items() if r == (30, 16, 8, 2)]; assert roots
		assert any([f[-1] for f in fields if f[0] == n] == [0, 8] for n in roots)
		assert b'(field 0.0) F64' in c0_nabi and b'(field 1.0) F64' in c0_nabi
	if name == 'record-nominal':
		nominal = [n for n, r in records.items() if r == (30, 4, 4, 1)]; assert len(nominal) >= 2
		assert len({f[2] for f in fields if f[0] in nominal}) >= 2
		assert len(re.findall(rb'\(struct-value-plan #\d+', c0_nabi)) >= 2
	if name.startswith('method-'):
		classes = [n for n, r in types.items() if r == (31, 8, 8, 0)]; assert classes
		functions = [list(map(int, r[1:])) for r in rows if r[0] == 'FUNCTION']
		assert any(f[6] == 0 for f in functions)
		channels = [list(map(int, r[1:])) for r in rows if r[0] == 'CHANNEL']
		assert any(c[1] == 0 and c[2] in classes and c[3:] == [2, 8] for c in channels)
	return dict(author_layouts_checked=name.startswith(('record-', 'method-')), c0_leaf_correspondence=name.startswith('record-'), private_calling_convention='C0 flattening and Astra aggregate/pointer transport are separately retained')
