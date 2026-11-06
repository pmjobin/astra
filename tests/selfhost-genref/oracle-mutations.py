#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Falsify the separate Python oracle with actual source-bound graph variants."""
import argparse
import copy
import json
from pathlib import Path
from oracle import Model, Refusal
from state import RUNTIME, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--input', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args()
	leaf = RUNTIME/('oracle-mutants-'+a.version+'-'+a.mode); leaf.mkdir(exist_ok=False)
	base = Model(a.input); valid = base.verify(); assert valid['status'] == 'PASS'
	selected = []
	for ordinal, plan in base.tables['INSTANCE'].items():
		offset = 0
		for source, before in base.tables['B_REF'].items():
			if before[0] not in base.pairs[ordinal]: continue
			number = plan[3]+offset; actual = base.tables['C_REF'][number]
			if before[8] == 1 and before[6] in base.symbols[ordinal] and actual[6] != before[6] and actual[5] != before[5]: selected.append((ordinal, source, number))
			offset += 1
	assert selected; ordinal, source, number = selected[0]; plan = base.tables['INSTANCE'][ordinal]; row = base.tables['C_REF'][number]; before = base.tables['B_REF'][source]
	def table(model, label, key, column, value):
		values = list(model.tables[label][key]); values[column] = value; model.tables[label][key] = tuple(values)
	mutants = []
	for name, column, value in [('wrong-node', 0, before[0]), ('wrong-token', 1, row[1]+1), ('wrong-source', 2, row[2]+1), ('wrong-start', 3, row[3]+1), ('wrong-end', 4, row[4]+1), ('stale-scope', 5, before[5]), ('unmapped-target', 6, before[6]), ('dead-target', 6, 0), ('wrong-alternative', 7, row[6]), ('unresolved-state', 8, 5), ('wrong-reason', 9, 7), ('wrong-domain', 10, 4), ('reverse-chain-cycle', 11, number)]:
		mutants.append((name, lambda m, c=column, v=value: table(m, 'C_REF', number, c, v)))
	mutants += [
		('missing-reference-count', lambda m: table(m, 'INSTANCE', ordinal, 4, plan[4]-1)),
		('extra-reference-count', lambda m: table(m, 'INSTANCE', ordinal, 4, plan[4]+1)),
		('wrong-range-start', lambda m: table(m, 'INSTANCE', ordinal, 3, plan[3]+1)),
		('node-chain-cycle', lambda m: table(m, 'REF_NEXT', number, 0, number)),
		('missing-node-head', lambda m: table(m, 'REF_HEAD', row[0], 0, 0)),
		('missing-reverse-head', lambda m: table(m, 'C_SYMBOL', row[6], 11, 0)),
		('forged-symbol-owner', lambda m: table(m, 'C_SYMBOL', row[6], 6, 0)),
		('wrong-scope-parent', lambda m: table(m, 'C_SCOPE', row[5], 2, 0)),
		('missing-builder-node-map', lambda m: m.maps['MAP_NODE'][ordinal].pop(before[0])),
		('wrong-builder-symbol-map', lambda m: m.maps['MAP_SYMBOL'][ordinal].__setitem__(before[6], before[6])),
		('wrong-builder-scope-map', lambda m: m.maps['MAP_SCOPE'][ordinal].__setitem__(before[5], before[5])),
	]
	methods = [(p, row) for p, row in base.tables['INSTANCE'].items() if row[2] and base.tables['B_SYMBOL'][row[0]][7] == 11]
	pair = next((left, right) for left in methods for right in methods if left[1][0] == right[1][0] and left[1][2] != right[1][2])
	outer_method, other_method = pair
	mutants.append(('wrong-same-layout-outer-specialization', lambda m: table(m, 'INSTANCE', outer_method[0], 2, other_method[1][2])))
	classes = [(p, row) for p, row in base.tables['INSTANCE'].items() if base.tables['B_SYMBOL'][row[0]][7] == 4]
	left, right = next((left, right) for left in classes for right in classes if left[1][0] == right[1][0] and left[1][7:] != right[1][7:])
	mutants.append(('forged-duplicate-nominal-specialization-key', lambda m: table(m, 'INSTANCE', left[0], 7, right[1][7])))
	root = base.tables['C_SYMBOL'][outer_method[1][1]][0]; hidden = base.children(root, 'parameters')[0]; hidden_symbol = base.symbol_nodes[hidden][0]
	mutants.append(('lost-hidden-receiver-borrow', lambda m: table(m, 'SYMBOL_TYPE', hidden_symbol, 1, 4)))
	results = []
	for name, forge in mutants:
		model = copy.deepcopy(base); forge(model)
		try: model.verify()
		except Refusal as error: result = dict(category=name, independent_rejection=error.category, witness=error.detail)
		else: raise AssertionError('oracle admitted '+name)
		assert base.verify()['status'] == 'PASS'; results.append(result)
		print(a.mode, name, result['independent_rejection'], 'VALID_RESTORED', flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, input_sha256=sha(a.input), oracle_sha256=sha(Path(__file__).with_name('oracle.py')), mutations=results, valid_twin=valid, boundary='Separate Python reconstruction from raw original AST/Binder facts; these mutations are distinct from the actual Astra consumer mutation campaign and are not added to its category count.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
