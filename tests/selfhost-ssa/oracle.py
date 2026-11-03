# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent graph sets and reaching-definition sets over produced SSA.

No lowering, syntax recognition, builder caches or expected dump strings.
"""
from collections import Counter, defaultdict


def records(data):
	out = defaultdict(list)
	for line in data.decode().splitlines():
		x = line.split()
		if x:
			out[x[0]].append(x[1:])
	return out


def table(rows, name):
	return {int(x[0]): list(map(int, x[:18] if name == 'INST' else x)) for x in rows.get(name, [])}


def graph_facts(blocks, edges, entries):
	parents = {b: set() for b in blocks}
	children = {b: set() for b in blocks}
	for _, src, dst in edges:
		parents[dst].add(src)
		children[src].add(dst)
	live = set()
	pending = list(entries)
	while pending:
		b = pending.pop()
		if b not in live:
			live.add(b)
			pending.extend(children[b])
	dom = {b: ({b} if b in entries else set(live)) for b in live}
	changed = True
	iterations = 0
	while changed:
		changed = False
		iterations += 1
		assert iterations <= len(live)+2
		for b in sorted(live):
			if b in entries:
				continue
			ps = parents[b] & live
			value = {b} | set.intersection(*(dom[p] for p in ps))
			if value != dom[b]:
				dom[b] = value
				changed = True
	idom = {}
	for b in blocks:
		strict = dom.get(b, set())-{b}
		idom[b] = max(strict, key=lambda x: len(dom[x])) if strict else 0
	frontier = {(d, dst) for _, src, dst in edges if src in live for d in dom[src] if d == dst or d not in dom[dst]}
	return live, parents, dom, idom, frontier


def inspect(data, frozen_cfg, facts):
	assert data.startswith(b'astra-ssa/1\n')
	cfg = data.split(b'\n', 1)[1].split(b'SSA_META', 1)[0]
	assert cfg == frozen_cfg, 'retained CFG/source authority changed'
	r = records(data)
	blocks = table(r, 'BLOCK')
	inst = table(r, 'INST')
	values = table(r, 'SSA_VALUE')
	variables = table(r, 'SSA_VAR')
	uses = table(r, 'SSA_USE')
	args = table(r, 'SSA_ARG')
	ssa_inst = table(r, 'SSA_INST')
	ssa_blocks = table(r, 'SSA_BLOCK')
	edges = {int(x[0]): list(map(int, x)) for x in r.get('SUCC', [])}
	entries = {int(x[1]) for x in r.get('CFG_FUNCTION', [])}
	live, parents, dom, idom, frontier = graph_facts(blocks, [(e[0], e[2], e[3]) for e in edges.values()], entries)
	assert table(r, 'SSA_DOM_BLOCK') == {b: [b, idom[b], int(b in live)] for b in blocks}
	assert {tuple(map(int, x)) for x in r.get('SSA_DOM', [])} == {(d, b) for b in live for d in dom[b]}
	assert {tuple(map(int, x)) for x in r.get('SSA_FRONTIER', [])} == frontier
	assert len(ssa_inst) == len(inst)
	assert len(ssa_blocks) == len(blocks)
	for i, row in ssa_inst.items():
		assert row[4] == 0, 'unproved noalias'
		assert row[5:13] == inst[i][1:9]
	for b, row in ssa_blocks.items():
		assert row[2:] == blocks[b][1:]
	phis = {(v[5], v[3]): v[0] for v in values.values() if v[2] == 3}
	writes = {(v[5], v[3]): v[0] for v in values.values() if v[2] == 1 and v[5]}
	assert len(phis) == sum(v[2] == 3 for v in values.values())
	assert len(writes) == sum(v[2] == 1 and bool(v[5]) for v in values.values())
	claimed = [v[4] for v in values.values() if v[2] == 1]
	assert len(claimed) == len(set(claimed))
	for v in values.values():
		_, f, kind, b, instruction, variable, place, typ, flags = v
		assert blocks[b][1] == f
		if kind == 1:
			assert ssa_inst[instruction][1:3] == [v[0], variable]
			assert inst[instruction][1] == b
		elif kind == 2:
			assert b in entries and place
		else:
			assert kind == 3 and variable and 1 <= typ <= 13 and not flags
			assert variables[variable][1] == f and variables[variable][4] == typ
			assert len([e for e in edges.values() if e[3] == b and e[2] in live]) >= 2
			# Independent set-valued forward equations, with writes and block arguments
			# as cut points. This also checks stale versions that still dominate a use.
	before = {}
	after = {}
	for var, variable in variables.items():
		out = {b: set() for b in live}
		changed = True
		iterations = 0
		while changed:
			changed = False
			iterations += 1
			assert iterations <= len(live)+len(values)+2
			for b in sorted(live):
				if blocks[b][1] != variable[1]:
					continue
				incoming = set().union(*(out[p] for p in parents[b] & live))
				if b in entries:
					incoming = {variable[5]} if variable[5] else set()
				if (var, b) in phis:
					incoming = {phis[var, b]}
				before[var, b] = incoming
				value = {writes[var, b]} if (var, b) in writes else incoming
				if value != out[b]:
					out[b] = value
					changed = True
		for b in live:
			after[var, b] = out[b]
	place_variables = {v[3]: v[0] for v in variables.values() if v[2] == 2}
	temp_variables = {v[3]: v[0] for v in variables.values() if v[2] == 1}
	temps = {i[4]: ssa_inst[i[0]][1] for i in inst.values() if i[4] and i[3] != 44}
	expected = []
	for b, block in blocks.items():
		f = block[1]
		if block[4]:
			i = inst[block[4]]
			if i[3] < 40 or i[3] == 44:
				for kind, source in ((1, i[5]), (2, i[6])):
					if source:
						expected.append([f, b, i[0], kind, 0, source, 0, 0])
			if i[3] == 3 and i[12] in place_variables:
				expected.append([f, b, i[0], 4, 0, i[12], 0, 0])
			if i[3] in (9, 10):
				for arg in sorted((list(map(int, x)) for x in r.get('ARG', []) if int(x[2]) == i[0]), key=lambda x: x[3]):
					expected.append([f, b, i[0], 3, arg[3], arg[4], arg[5], arg[6]])
		if block[7]:
			expected.append([f, b, 0, 5, 0, block[7], 0, 0])
	assert [u[1:9] for u in uses.values()] == expected
	refcounts = Counter()
	for u in uses.values():
		_, f, b, instruction, kind, ordinal, source, label, mode, value = u
		if b not in live:
			assert value == 0
			continue
		v = values[value]
		assert v[1] == f and v[3] in dom[b] and (v[2] != 1 or v[3] != b)
		variable = (place_variables if kind == 4 else temp_variables).get(source)
		if variable:
			assert before[variable, b] == {value}, ('stale use', u, before[variable, b])
		else:
			assert temps[source] == value
		refcounts[value] += 1
	for phi in (v for v in values.values() if v[2] == 3):
		incoming = [a for a in args.values() if a[2] == phi[0]]
		expected_edges = [e[0] for e in edges.values() if e[3] == phi[3]]
		assert [a[3] for a in incoming] == expected_edges
		for a in incoming:
			e = edges[a[3]]
			if e[2] not in live:
				assert a[4] == 0
			else:
				assert after[phi[5], e[2]] == {a[4]}
				v = values[a[4]]
				assert v[3] in dom[e[2]] and v[1] == phi[1] and v[7:] == phi[7:]
				refcounts[a[4]] += 1
	assert table(r, 'DEF_USE') == {v: [v, refcounts[v]] for v in values}
	place_phis = [v for v in values.values() if v[2] == 3 and variables[v[5]][2] == 2]
	temp_phis = [v for v in values.values() if v[2] == 3 and variables[v[5]][2] == 1]
	if facts.get('place_phi'):
		assert place_phis
	if facts.get('temp_phi'):
		assert temp_phis
	if facts.get('loop_phi'):
		assert any(values[a[2]][3] in dom.get(edges[a[3]][2], set()) for a in args.values())
	if facts.get('dead'):
		assert set(blocks)-live
	if facts.get('memory'):
		assert any(i[3] == 22 and not ssa_inst[i[0]][3] for i in inst.values())
	if facts.get('stores'):
		assert sum(i[3] in (21, 22) for i in inst.values()) == facts['stores']
	if facts.get('functions'):
		assert len(entries) == facts['functions']
	if facts.get('cleanup'):
		assert any(i[3] == 40 for i in inst.values())
	if facts.get('loans'):
		assert sum(i[3] == 42 for i in inst.values()) == sum(i[3] == 43 for i in inst.values()) > 0
	if facts.get('distinct_equal'):
		payload = {int(x[0]): x[1] for x in r['PAYLOAD']}
		matched = False
		for phi in place_phis:
			incoming = [a[4] for a in args.values() if a[2] == phi[0] and a[4]]
			if len(set(incoming)) < 2:
				continue
			origins = [inst[values[v][4]] for v in incoming if values[v][2] == 1]
			if len(origins) == len(incoming) and all(i[3] == 22 and payload.get(i[5]) == '37' for i in origins):
				matched = True
		assert matched, 'equal literals must have distinct producer definitions'
	return dict(blocks=len(blocks), reachable=len(live), values=len(values), phis=len(phis), place_phis=len(place_phis), temp_phis=len(temp_phis), uses=len(uses), arguments=len(args))


def synthetic(data):
	results = []
	for part in data.decode().split('SYNTH ')[1:]:
		lines = part.splitlines()
		shape, size = map(int, lines[0].split())
		r = records(('\n'.join(lines[1:])+'\n').encode())
		edges = [list(map(int, x)) for x in r.get('EDGE', [])]
		live, parents, dom, idom, frontier = graph_facts(range(1, size+1), edges, {1})
		assert table(r, 'BLOCK') == {b: [b, idom[b], int(b in live)] for b in range(1, size+1)}
		assert {tuple(map(int, x)) for x in r.get('DOM', [])} == {(d, b) for b in live for d in dom[b]}
		assert {tuple(map(int, x)) for x in r.get('FRONTIER', [])} == frontier
		results.append(dict(shape=shape, size=size, edges=len(edges), reachable=len(live)))
	assert len(results) == 7
	return results
