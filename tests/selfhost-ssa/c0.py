# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Normalize comparable C0 SSA facts without comparing value/block numbering."""
from collections import Counter, defaultdict
import json
import re
from oracle import records, table

COMPARABLE = {'ssa-diamond', 'ssa-nested-diamond', 'ssa-chain', 'ssa-same-literal', 'ssa-counter', 'ssa-and-skip', 'ssa-or-skip', 'ssa-and-evaluate', 'ssa-break-version', 'ssa-overwrite-join'}


def sexpr(data):
	root = []
	stack = [root]
	for token in re.findall(r'"(?:\\.|[^"\\])*"|[()]|[^\s()]+', data.decode()):
		if token == '(':
			x = []
			stack[-1].append(x)
			stack.append(x)
			assert len(stack) <= 512
		elif token == ')':
			assert len(stack) > 1
			stack.pop()
		else:
			stack[-1].append(json.loads(token) if token.startswith('"') else token)
	assert len(stack) == 1 and len(root) == 1
	return root[0]


def reference(tree):
	functions = [x for x in tree[1:] if isinstance(x, list) and x[0] == 'function']
	facts = []
	for function in functions:
		name = function[2]
		definitions = {}
		phis = {}
		parameters = {}
		blocks = [x for x in function if isinstance(x, list) and x[0] == 'block']
		for item in function:
			if isinstance(item, list) and item[0] == 'parameters':
				for p in item[1:]:
					parameters[p[0]] = p[1]
		incoming = defaultdict(list)
		used = Counter()
		def references(row):
			if isinstance(row, str):
				if row.startswith('%'):
					used[row] += 1
			else:
				for child in row:
					references(child)
		for block in blocks:
			for row in block[2:]:
				if row[0] != 'arguments':
					references(row[1:] if row[0].startswith('%') else row)
				if row[0] == 'arguments':
					for ordinal, p in enumerate(row[1:]):
						phis[p[0]] = p[1] if isinstance(p[1], str) else 'temporary'
						incoming[block[1], ordinal]
				elif '=' in row:
					definitions[row[0]] = row[row.index('=')+1:]
		def expr(x):
			if isinstance(x, str):
				if x in phis:
					return ('phi', phis[x])
				if x in parameters:
					return ('parameter', parameters[x])
				return expr(definitions[x])
			if x[0] in ('integer', 'bool'):
				return (x[0], x[1])
			if x[0] == 'binary':
				return ('binary', x[1], expr(x[2]), expr(x[3]))
			if x[0] == 'call':
				return ('call', x[2])
			raise AssertionError(('unmapped C0 expression', x))
		for block in blocks:
			for row in block[2:]:
				branches = []
				if row[0] == 'branch':
					branches.append(row[1:])
				if row[0] == 'conditional-branch':
					branches.extend(x[1:] for x in row[2:] if isinstance(x, list))
				for target, arguments in branches:
					for ordinal, argument in enumerate(arguments):
						incoming[target, ordinal].append(expr(argument))
		for block in blocks:
			for row in block[2:]:
				if row[0] == 'arguments':
					for ordinal, p in enumerate(row[1:]):
						if used[p[0]]:
							facts.append((name, phis[p[0]], tuple(sorted(map(repr, incoming[block[1], ordinal])))))
	return facts


def candidate(data):
	r = records(data)
	values = table(r, 'SSA_VALUE')
	variables = table(r, 'SSA_VAR')
	inst = table(r, 'INST')
	nodes = {int(x[0]): list(map(int, x[:15])) for x in r['NODE']}
	places = table(r, 'PLACE')
	decl = {int(x[0]): bytes.fromhex(x[6]).decode() for x in r['DECL']}
	functions = {int(x[0]): decl[int(x[1])] for x in r['FUNCTION']}
	payload = {int(x[0]): x[1:] for x in r['PAYLOAD']}
	uses = table(r, 'SSA_USE')
	arguments = table(r, 'SSA_ARG')
	def variable_name(v):
		var = variables[v[5]]
		return decl[places[var[3]][4]].split('.')[-1] if var[2] == 2 else 'temporary'
	def expr(value, depth=0):
		assert depth < 256
		v = values[value]
		if v[2] == 3:
			return ('phi', variable_name(v))
		if v[2] == 2:
			return ('parameter', decl[places[v[6]][4]].split('.')[-1])
		i = inst[v[4]]
		operands = {u[4]: u[9] for u in uses.values() if u[3] == v[4] and u[4] != 3}
		if i[3] in (1, 2):
			literal = bytes.fromhex(payload[i[2]][0]).decode()
			return ('bool' if v[7] == 13 else 'integer', literal)
		if i[3] == 3 and 4 in operands:
			return expr(operands[4], depth+1)
		if i[3] == 44 and i[5] == nodes[i[2]][6]:
			# C0 canonicalizes the skipped AND/OR edge to false/true. Native
			# CFG copies the guard value on that exact edge. The edge predicate
			# supplies this fact, even when a constant guard makes it untaken.
			operator = bytes.fromhex(payload[i[2]][1]).decode()
			return ('bool', 'false' if operator == '&&' else 'true')
		if i[3] in (12, 21, 22, 44):
			return expr(operands[1], depth+1)
		if i[3] == 6:
			return ('binary', bytes.fromhex(payload[i[2]][1]).decode(), expr(operands[1], depth+1), expr(operands[2], depth+1))
		if i[3] == 9:
			return ('call', decl[i[13]])
		raise AssertionError(('unmapped native expression', i))
	facts = []
	for v in values.values():
		if v[2] == 3:
			incoming = [expr(a[4]) for a in arguments.values() if a[2] == v[0] and a[4]]
			facts.append((functions[v[1]], variable_name(v), tuple(sorted(map(repr, incoming)))))
	return facts


def compare(name, data, reference_data):
	tree = sexpr(reference_data)
	names = [x[2] for x in tree[1:] if isinstance(x, list) and x[0] == 'function']
	r = records(data)
	decl = {int(x[0]): bytes.fromhex(x[6]).decode() for x in r['DECL']}
	assert names == [decl[int(x[1])] for x in r['FUNCTION']]
	result = dict(functions=names, phi_comparison='not selected')
	if name in COMPARABLE:
		c0 = reference(tree)
		native = candidate(data)
		assert c0 and not (Counter(c0)-Counter(native)), (name, c0, native)
		result.update(phi_comparison='normalized incoming expressions', c0=c0, native=native, redundant_native_phis=len(native)-len(c0))
	return result
