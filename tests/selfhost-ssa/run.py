#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused source-bound SSA, predecessor compatibility and mutation checks."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import subprocess
import time
from oracle import inspect, synthetic
from c0 import compare

MUTATIONS = ['wrong-incoming-value', 'missing-input', 'extra-input', 'duplicate-definition', 'wrong-edge', 'cross-function-value', 'type-identity', 'use-before-definition', 'non-dominating-use', 'stale-version', 'forged-idom', 'forged-frontier', 'lost-loop-backedge', 'move-as-copy', 'loan-past-cleanup', 'reordered-arguments', 'dropped-release', 'double-release', 'wrong-block', 'wrong-source', 'forged-success', 'bogus-noalias', 'work-exhaustion', 'wrong-cleanup-owner', 'wrong-place', 'literal-spelling', 'reordered-effects', 'wrong-short-circuit-source', 'owning-phi', 'wrong-function-parameter']
CORE_CASES = {'scalar-control', 'equal-paths', 'nested-channel', 'short-loan', 'channel-borrow'}
CFG_CASES = {'nested-loops', 'short-skip', 'ordered-owned-arguments', 'nested-owner-leaves', 'owner-loop-exits', 'owner-conditional-return'}
SSA_CASES = {'ssa-diamond', 'ssa-counter', 'ssa-and-skip', 'ssa-argument-order', 'ssa-borrow-end', 'ssa-field-memory', 'owner-loop-exits', 'nested-owner-leaves'}


def sha(data):
	return hashlib.sha256(data).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('build', 'runtime', 'frozen'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', action='append')
	p.add_argument('--development', action='store_true')
	p.add_argument('--product-prefix', default='astra-ssa-')
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	commands = []
	results = []
	mutations = {}
	products = {}
	items = json.loads((a.frozen/'cases.json').read_text())
	assert len(items) == 80
	assert Counter(x['core_status'] for x in items[:47]) == {0: 23, 4: 12, 3: 12}
	def run(argv, name, expected):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], capture_output=True, timeout=60)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stdout_sha256=sha(r.stdout)))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, expected, r.stderr.decode()[-2000:])
		return r
	for mode in a.mode or ('O0', 'O2'):
		exe = a.build/(a.product_prefix+mode)
		identity = json.loads(exe.with_suffix('.identity.json').read_text())
		assert sha(exe.read_bytes()) == identity['sha256']
		assert all(sha(Path(p).read_bytes()) == h for p, h in identity['identity']['sources'].items())
		products[mode] = dict(path=str(exe), sha256=sha(exe.read_bytes()), identity_sha256=sha(exe.with_suffix('.identity.json').read_bytes()))
		killed = dict(core=set(), cfg=set(), ssa=set())
		mutation_rows = []
		r = run([exe, '--ssa-graphs'], 'synthetic-'+mode, 0)
		graphs = synthetic(r.stdout)
		for item in items:
			assert sha(Path(item['paths'][0]).read_bytes()) == item['sha256']
			name = item['name']+'-'+mode
			r = run([exe, '--ssa', *item['paths']], name, item['core_status'])
			if item['core_status']:
				assert not r.stdout and r.stderr.startswith(b'SSA_DEFERRED' if item['core_status'] == 3 else b'INVALID_VERIFIED_CFG')
			else:
				facts = inspect(r.stdout, (a.frozen/(name+'-cfg.stdout')).read_bytes(), item.get('facts', {}))
				c0 = compare(item['name'], r.stdout, (a.frozen/(item['name']+'-C0-ssa.stdout')).read_bytes())
				results.append(dict(name=item['name'], mode=mode, source_sha256=item['sha256'], facts=facts, c0=c0))
			print(name, r.returncode, flush=True)
			if a.development:
				continue
			for stage in ('--admit', '--core', '--cfg'):
				old = a.frozen/(name+'-'+stage[2:])
				# Admission uses its original status vocabulary, distinct from Core.
				expected = item['core_status'] if stage != '--admit' else None
				if expected is None:
					previous = next(x for x in json.loads((a.frozen/'commands.json').read_text()) if x['argv'][1] == stage and x['argv'][0].endswith(mode) and x['argv'][2:] == item['paths'])
					expected = previous['exit']
				q = run([exe, stage, *item['paths']], name+'-'+stage[2:], expected)
				assert q.stdout == old.with_suffix('.stdout').read_bytes() and q.stderr == old.with_suffix('.stderr').read_bytes(), (name, stage, 'predecessor byte drift')
			if item['core_status']:
				continue
			for layer, selection in [('core', CORE_CASES), ('cfg', CFG_CASES), ('ssa', SSA_CASES)]:
				if item['name'] not in selection:
					continue
				q = run([exe, '--mutate-'+layer, *item['paths']], name+'-mutate-'+layer, 0)
				for line in q.stdout.decode().splitlines():
					x = line.split()
					assert x[0] == layer.upper()+'_MUTATION'
					index = int(x[1])
					killed[layer].add(index)
					if layer in ('ssa', 'cfg'):
						before, after, restored = map(bytes.fromhex, x[3:])
						assert before == restored and before != after
						mutation_rows.append(dict(case=item['name'], layer=layer, index=index, status=int(x[2]), before_sha256=sha(before), after_sha256=sha(after), restored_sha256=sha(restored)))
		if not a.development:
			assert killed['core'] == set(range(22)), sorted(killed['core'])
			assert killed['cfg'] == set(range(26)), sorted(killed['cfg'])
			assert killed['ssa'] == set(range(30)), sorted(killed['ssa'])
		mutations[mode] = dict(categories={k: sorted(v) for k, v in killed.items()}, receipts=mutation_rows, synthetic=graphs)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='DEVELOPMENT' if a.development else 'PASS', outcomes=dict(Counter(x['core_status'] for x in items)), inherited_cfg_positives=sum(x['core_status'] == 0 for x in items[:62]), new_witnesses=18, products=products, cases=results, mutations=mutations), indent=2)+'\n')


if __name__ == '__main__':
	main()
