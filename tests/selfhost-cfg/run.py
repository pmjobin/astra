#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent graph/def-use/partial-order checks against frozen source and C0.

No compiler lowering lives here. The worklist reads produced CFG tables, checks
all reachable definitions and uses, and compares typed authority with frozen Core.
"""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


MUTATIONS = ['true-false-swap', 'dangling-predecessor', 'duplicate-terminator', 'wrong-loop-exit', 'wrong-function-owner', 'dropped-return', 'short-circuit-polarity', 'eager-rhs', 'argument-order', 'callee-identity', 'value-as-place', 'move-as-copy-double-owner', 'omitted-cleanup', 'duplicate-cleanup-cycle', 'cleanup-order', 'wrong-cleanup-edge', 'early-loan-end', 'source-span', 'undefined-temporary', 'forged-status', 'resource-limit', 'orphan-reachable-block', 'wrong-load-type', 'late-loan-end', 'unconditional-cleanup']


def sha(data):
	return hashlib.sha256(data).hexdigest()


def rows(data, version=b'astra-cfg/1'):
	assert data.splitlines()[0] == version
	out = {}
	for line in data.decode().splitlines()[1:]:
		x = line.split()
		out.setdefault(x[0], []).append(x[1:])
	return out


def inspect(data, frozen, facts):
	r = rows(data)
	core = rows(frozen, b'astra-core/1')
	for kind in ('SOURCE', 'DECL', 'SIGNATURE', 'CHECKED', 'PROOF', 'FUNCTION', 'PLACE', 'EDGE', 'EXIT', 'CLEANUP', 'LOAN', 'NODE', 'PAYLOAD'):
		assert r.get(kind, []) == core.get(kind, []), ('source authority changed', kind)
	blocks = {int(x[0]): list(map(int, x[:11])) for x in r['BLOCK']}
	inst = {int(x[0]): list(map(int, x[:18])) for x in r.get('INST', [])}
	nodes = {int(x[0]): list(map(int, x[:15])) for x in r['NODE']}
	edges = [list(map(int, x)) for x in r.get('SUCC', [])]
	preds = [list(map(int, x)) for x in r.get('PRED', [])]
	assert len(edges) == len(preds)
	assert Counter((x[1], x[0], x[2], x[3]) for x in edges) == Counter(tuple(x[1:]) for x in preds)
	functions = {int(x[0]): list(map(int, x)) for x in r['CFG_FUNCTION']}
	parents = {b: set() for b in blocks}
	for e in edges:
		_, f, src, dst, polarity = e
		assert blocks[src][1] == blocks[dst][1] == f
		assert blocks[src][7 + polarity] == dst
		parents[dst].add(src)
	live = set()
	pending = [x[1] for x in functions.values()]
	while pending:
		at = pending.pop()
		if at in live: continue
		live.add(at)
		pending.extend(x for x in blocks[at][8:10] if x)
	assert live == {b for b,x in blocks.items() if x[10]}
	# Must-definition intersection over the actual graph, including backedges.
	universe = {x[4] for x in inst.values() if x[4]}
	defs_in = {b: set(universe) for b in live}
	entries = {x[1] for x in functions.values()}
	defs_out = {b: set(universe) for b in live}
	iterations = 0
	changed = True
	while changed:
		changed = False
		iterations += 1
		assert iterations <= len(live) + 2
		for b in sorted(live):
			ps = parents[b] & live
			before = set.intersection(*(defs_out[p] for p in ps)) if ps and b not in entries else set()
			after = set(before)
			if blocks[b][4] and inst[blocks[b][4]][4]: after.add(inst[blocks[b][4]][4])
			if before != defs_in[b] or after != defs_out[b]: changed = True
			defs_in[b] = before; defs_out[b] = after
	for b in live:
		x = blocks[b]
		assert x[5] == 1 and x[6] != 4
		uses = []
		if x[6] in (2, 3) and x[7]: uses.append(x[7])
		if x[4]:
			i = inst[x[4]]
			_, block, origin, op, result, a, bb, contract, guarded = i[:9]
			assert block == b
			if op < 40:
				if a: uses.append(a)
				if bb: uses.append(bb)
				if op in (9, 10):
					uses.extend(int(e[4]) for e in r['ARG'] if int(e[2]) == i[0])
			if op == 44: uses.append(a)
			if op == 40: assert guarded == 1 and 1 <= contract <= len(r['CLEANUP'])
		assert set(uses) <= defs_in[b], ('temp read before definition', b, uses, defs_in[b])
	ops = Counter(x[3] for x in inst.values())
	kinds = Counter(x[1] for x in nodes.values())
	for key, kind in [('returns', 27), ('branches', 23), ('loops', 24), ('short', 7), ('calls', 9), ('moves', 4), ('breaks', 25), ('continues', 26)]:
		if key in facts: assert kinds[kind] == facts[key], (key, kinds[kind], facts[key])
	if facts.get('cleanup'): assert ops[40]
	if facts.get('loans'): assert ops[42] == ops[43] and ops[42] > 0
	# Every source operation has one physical evaluation block. Short-circuit
	# values have two path-specific definitions and one explicit guard instead.
	for node in nodes.values():
		id, kind = node[:2]
		matching = [x for x in inst.values() if x[2] == id and x[3] == kind]
		if kind in (*range(1, 7), *range(8, 13), 21, 22, 28): assert len(matching) == 1
		if kind == 7:
			copies = [x for x in inst.values() if x[2] == id and x[3] == 44]
			assert len(copies) == 2 and {x[5] for x in copies} == {node[6], node[7]}
			guards = [x for x in blocks.values() if x[2] == id and x[3] == 7]
			assert len(guards) == 1 and guards[0][7] == node[6]
	walk = list(map(int, r['CFG_WALK'][0]))
	assert walk[0] == len(live)
	assert walk[1] == sum(e[2] in live for e in edges)
	assert walk[2] == sum(len(parents[b] & live) > 1 for b in live)
	if facts.get('loops'): assert walk[3] >= facts['loops']
	return dict(blocks=len(blocks), reachable=len(live), instructions=len(inst), edges=len(edges), definition_iterations=iterations, walk=walk)


def main():
	p = argparse.ArgumentParser()
	for key in ('build', 'runtime', 'frozen'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', action='append')
	p.add_argument('--development', action='store_true')
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	commands = []
	def run(argv, name, expected):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], capture_output=True)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stdout_sha256=sha(r.stdout)))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, expected, r.stderr.decode()[-2000:])
		return r
	results = []
	mutations = {}
	for mode in a.mode or ('O0', 'O2'):
		exe = a.build/('astra-cfg-'+mode)
		identity = json.loads(exe.with_suffix('.identity.json').read_text())
		assert identity['sha256'] == sha(exe.read_bytes())
		assert all(sha(Path(p).read_bytes()) == h for p,h in identity['identity']['sources'].items())
		killed = set()
		items = json.loads((a.frozen/'cases.json').read_text())
		if (a.frozen/'supplemental.json').exists(): items.extend(json.loads((a.frozen/'supplemental.json').read_text()))
		for item in items:
			name = item['name']+'-'+mode
			assert sha(Path(item['paths'][0]).read_bytes()) == item['sha256']
			r = run([exe, '--cfg', *item['paths']], name, item['core_status'])
			if item['core_status']:
				assert not r.stdout and r.stderr.startswith(b'CFG_DEFERRED' if item['core_status'] == 3 else b'INVALID_VERIFIED_CORE')
				continue
			comparison = inspect(r.stdout, (a.frozen/(item['name']+'-core-'+mode+'.stdout')).read_bytes(), item.get('facts', {}))
			results.append(dict(name=item['name'], mode=mode, sha256=item['sha256'], comparison=comparison))
			print(name, comparison['blocks'], flush=True)
			if a.development: continue
			if item['name'] in ('nested-loops', 'short-skip', 'ordered-owned-arguments', 'nested-owner-leaves', 'owner-loop-exits', 'owner-conditional-return'):
				r = run([exe, '--mutate-cfg', *item['paths']], name+'-mutations', 0)
				for line in r.stdout.decode().splitlines():
					x = line.split()
					if x[0] != 'CFG_MUTATION': continue
					index, status = map(int, x[1:3]); assert status in (1, 2)
					before = bytes.fromhex(x[3]); after = bytes.fromhex(x[4]); restored = bytes.fromhex(x[5])
					assert before == restored and before != after
					killed.add(index)
					mutations.setdefault(mode, []).append(dict(case=item['name'], mutation=index, family=MUTATIONS[index], status=status, before_sha256=sha(before), after_sha256=sha(after), restored_sha256=sha(restored)))
		if not a.development: assert len(killed) >= 18, (mode, sorted(killed))
	(a.runtime/'result.json').write_text(json.dumps(dict(status='DEVELOPMENT' if a.development else 'PASS', cases=results, mutations=mutations), indent=2)+'\n')


if __name__ == '__main__':
	main()
