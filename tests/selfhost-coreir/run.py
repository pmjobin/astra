#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare real typed Core graphs with frozen C0/source and manual invariants."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
from corpus import additional

ROOT = Path(__file__).resolve().parents[2]
MUTATIONS = ['load-type', 'function-owner', 'equal-nominal-root', 'projection-parent', 'value-as-place', 'callee', 'borrow-as-owned', 'argument-order', 'unconditional-rhs', 'omitted-cleanup', 'duplicate-cleanup', 'loan-end', 'forged-proof', 'branch-successor', 'source-span', 'cycle', 'resource-limit', 'move-as-copy', 'cleanup-order', 'loop-target', 'readonly-authority', 'unproved-alias-effect']


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def decode(data):
	rows = {}
	assert data.startswith(b'astra-core/1\n')
	for line in data.decode().splitlines()[1:]:
		x = line.split()
		rows.setdefault(x[0], []).append(x[1:])
	return rows


def structural(rows, c0, name):
	nodes = {int(r[0]): list(map(int, r[:15])) for r in rows['NODE']}
	kinds = Counter(n[1] for n in nodes.values())
	functions = rows.get('FUNCTION', [])
	counts = dict(functions=len(functions), returns=kinds[27], conditionals=kinds[23], loops=kinds[24], short_circuit=kinds[7], calls=kinds[9])
	oracle = dict(functions=len(re.findall(r'\(function "', c0)), returns=len(re.findall(r'\((?:struct-)?return(?:\s|\))', c0)), conditionals=len(re.findall(r'\(if(?:\s|\))', c0)), loops=len(re.findall(r'\(while #', c0)), short_circuit=len(re.findall(r'\(short-circuit ', c0)), calls=len(re.findall(r'\(call "', c0)))
	assert counts == oracle, (name, counts, oracle)
	names = {1:'int', 2:'i8', 3:'u8', 4:'i16', 5:'u16', 6:'u32', 7:'i64', 8:'u64', 9:'isize', 10:'usize', 11:'f32', 12:'f64', 13:'bool'}
	payload = {int(r[0]): bytes.fromhex(r[2]).decode() for r in rows.get('PAYLOAD', []) if r[2] != '-'}
	operations = Counter((payload[n[0]], names[n[4]]) for n in nodes.values() if n[1] in (6, 7))
	oracle_operations = Counter(re.findall(r'\((?:binary|short-circuit) ([^ ]+) : ([^\s)]+)', c0))
	assert operations == oracle_operations, (name, operations, oracle_operations)
	declarations = {int(r[0]): bytes.fromhex(r[6]).decode() for r in rows.get('DECL', [])}
	callees = Counter(declarations[n[10]] for n in nodes.values() if n[1] == 9)
	assert callees == Counter(re.findall(r'\(call "([^"]+)"', c0)), (name, 'callee identities', callees)
	assert kinds[4] == len(re.findall(r'\(record-move-value ', c0)), (name, 'owned record transfer count')


	places = {int(r[0]): list(map(int, r)) for r in rows.get('PLACE', [])}
	assert all(int(f[5]) in nodes for f in functions)
	assert all(n[4] > 0 for n in nodes.values())
	assert list(map(int, rows['WALK'][0]))[0] == len(nodes)
	max_depth = 0
	for p in places.values():
		seen = set()
		current = p[0]
		while current:
			assert current not in seen
			seen.add(current)
			current = places[current][3]
		max_depth = max(max_depth, len(seen)-1)
	assert len(nodes) > 0
	if name in ('existing-nested', 'existing-deep', 'nested-channel'):
		assert max_depth >= (5 if name == 'existing-deep' else 2)
		assert kinds[3] and kinds[21] and kinds[10]
	if name == 'equal-paths':
		roots = [p for p in places.values() if p[3] == 0]
		assert any(a[0] != b[0] and a[5] == b[5] for a in roots for b in roots)
	if name == 'scalar-control':
		assert kinds[24] == 1 and kinds[25] == 1 and kinds[26] == 1 and kinds[23] >= 4 and kinds[9] >= 5
	if name == 'short-loan':
		assert kinds[7] == 2 and kinds[4] == 2 and rows.get('CLEANUP')
	if name in ('channel-borrow', 'channel-forward-borrow', 'nested-channel'):
		assert rows.get('LOAN') and all(int(l[6]) != int(l[7]) for l in rows['LOAN'])
	if name in ('channel-consume', 'channel-forward', 'nested-channel'):
		assert kinds[4] and kinds[9] and rows.get('CLEANUP')
	return dict(counts=counts, maximum_field_depth=max_depth, nodes=len(nodes), places=len(places), exits=len(rows.get('EXIT', [])), cleanups=len(rows.get('CLEANUP', [])), loans=len(rows.get('LOAN', [])))


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'build', 'runtime', 'baseline'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--additional', type=Path, required=True)
	p.add_argument('--mode', action='append')
	p.add_argument('--second-profile-build', type=Path)
	p.add_argument('--development', action='store_true')
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False)
	modes = a.mode or ('O0', 'O2')
	commands = []
	def run(argv, name, expected=None):
		argv = list(map(str, argv))
		t = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *argv], cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, seconds=time.monotonic()-t, stdout_sha256=hashlib.sha256(r.stdout).hexdigest()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		if expected is not None:
			assert r.returncode == expected, (name, r.returncode, r.stderr.decode()[-3000:])
		return r
	items = json.loads((a.baseline/'frozen.json').read_text())
	for item in items:
		item['status'] = item.get('core_status', 3 if item['defer'] else 4 if item['error'] else 0)
		# A checked Binder/type error may precede a named semantic deferral.
		old = a.baseline.parent/(item['name']+'-admit-O0.stdout')
		if old.exists() and b'STATUS 1 ' in old.read_bytes(): item['status'] = 4
		item['core_reference'] = str(a.baseline.parent/(item['name']+'-dump-core.stdout'))
		if not Path(item['core_reference']).is_file(): item['core_reference'] = str(a.baseline/item['name']/'core.stdout')
	extra = {x['name']: x for x in additional()}
	for item in json.loads((a.additional/'frozen.json').read_text()):
		assert item['source'] == extra[item['name']]['source']
		item.update(extra[item['name']])
		item['core_reference'] = str(a.additional/item['name']/'core.stdout')
		items.append(item)
	products = {}
	for mode in modes:
		exe = (a.second_profile_build if mode == 'O2' and a.second_profile_build else a.build)/('astra-core-'+mode)
		identity = json.loads(exe.with_suffix('.identity.json').read_text())
		assert identity['sha256'] == sha(exe) and all(sha(p) == h for p, h in identity['identity']['sources'].items())
		products[mode] = dict(path=str(exe), sha256=sha(exe), identity=sha(exe.with_suffix('.identity.json')))
	(a.runtime/'products.json').write_text(json.dumps(products, indent=2)+'\n')
	results = []
	killed = {mode: set() for mode in modes}
	for item in items:
		assert sha(item['paths'][0]) == item['sha256']
		observations = []
		for mode in modes:
			exe = (a.second_profile_build if mode == 'O2' and a.second_profile_build else a.build)/('astra-core-'+mode)
			r = run([exe, '--core', *item['paths']], item['name']+'-'+mode)
			print(item['name'], mode, r.returncode, flush=True)
			if a.development: continue
			assert r.returncode == item['status'], (item['name'], mode, r.returncode, item['status'], r.stderr.decode())
			if item['status']:
				assert not r.stdout and r.stderr.splitlines()[0] in (b'CORE_DEFERRED', b'INVALID_CHECKED_INPUT')
				continue
			projection = decode(r.stdout)
			comparison = structural(projection, Path(item['core_reference']).read_text(), item['name'])
			observations.append(r.stdout)
			results.append(dict(name=item['name'], mode=mode, sha256=item['sha256'], comparison=comparison))
			if item['name'] in ('scalar-control', 'equal-paths', 'nested-channel', 'short-loan', 'channel-borrow'):
				mutant = run([exe, '--mutate-core', *item['paths']], item['name']+'-mutations-'+mode, 0)
				killed[mode].update(map(int, re.findall(rb'(?m)^CORE_MUTATION (\d+) ', mutant.stdout)))
		if observations: assert all(data == observations[0] for data in observations), item['name']+' profile drift'
	if not a.development:
		for mode in modes:
			assert killed[mode] == set(range(22)), (mode, sorted(killed[mode]))
			exe = (a.second_profile_build if mode == 'O2' and a.second_profile_build else a.build)/('astra-core-'+mode)
			for name in ('equal-paths', 'nested-channel', 'short-loan', 'channel-overlap', 'unknown-call'):
				item = next(x for x in items if x['name'] == name)
				r = run(['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe, '--core', *item['paths']], name+'-memory-'+mode, item['status'])
				assert b'ERROR SUMMARY: 0 errors' in r.stderr and not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]', r.stderr)
			for name in ('equal-paths', 'nested-channel', 'scalar-control'):
				item = next(x for x in items if x['name'] == name)
				mutants = run(['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe, '--mutate-core', *item['paths']], name+'-mutation-memory-'+mode, 0)
				assert b'ERROR SUMMARY: 0 errors' in mutants.stderr
			item = next(x for x in items if x['name'] == 'existing-nested')
			retained = run([exe, '--retain', *item['paths']], 'retained-'+mode, 0)
			assert retained.stdout.startswith(b'CORE_RETAINED ')
			retained_memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe, '--retain', *item['paths']], 'retained-memory-'+mode, 0)
			assert b'ERROR SUMMARY: 0 errors' in retained_memory.stderr
			cross = run([exe, '--cross-owner', *item['paths']], 'cross-owner-'+mode, 0)
			assert cross.stdout == b'CORE_CROSS_OWNER_REJECTED\n'
			r = run([exe, '--core-limit', '1', *item['paths']], 'resource-'+mode, 2)
			assert not r.stdout and r.stderr.splitlines()[0] == b'CORE_RESOURCE_EXHAUSTED'
	(a.runtime/'result.json').write_text(json.dumps(dict(status='DEVELOPMENT' if a.development else 'PASS', source_cases=len(items), admitted=sum(x['status'] == 0 for x in items), products=products, comparisons=results, mutations={mode: [MUTATIONS[i] for i in sorted(v)] for mode,v in killed.items()}), indent=2)+'\n')


if __name__ == '__main__':
	main()
