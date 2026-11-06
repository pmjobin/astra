#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""C0 parses the exact original whole methods; no candidate helper supplies ASTs."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import bounded_run, ROOT, RUNTIME, PRIOR, C0, COHORTS, read, sha, digest, load_module


def find(tree, tag, name):
	if not isinstance(tree, list): return []
	return ([tree] if tree[:1] == [tag] and ['name', name] in tree else []) + [found for child in tree for found in find(child, tag, name)]


def declaration_contract(tree, selected):
	if not isinstance(tree, list): return []
	result = []
	for i, child in enumerate(tree):
		if child is selected:
			assert i > 0; result.append(tree[i - 1])
		result.extend(declaration_contract(child, selected))
	return result


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args()
	leaf = RUNTIME/('source-oracle-'+a.version); leaf.mkdir(exist_ok=False)
	probe = load_module('effects_independent_C0_parser', ROOT/'tests/selfhost-classstorage/abi-probe.py')
	results = {}; traces = read(RUNTIME/'trace-static-v2/result.json')
	for name in COHORTS:
		trace = traces[name]; ledger = read(PRIOR/('ledger-v3-O0-'+name)/'ledger.json')
		decl = next(row for row in ledger['nodes'] if row['node'] == int(trace['declaration'][1])); paths = [('producer', Path(decl['path']), 'flow_graph'), ('caller', Path(trace['source']), 'flow_index')]
		rows = []
		for role, path, function in paths:
			start = time.monotonic(); argv = [str(C0), '--dump-syntax', str(path)]
			r = bounded_run(argv, capture_output=True, timeout=60)
			(leaf/(name+'-'+role+'.stdout')).write_bytes(r.stdout); (leaf/(name+'-'+role+'.stderr')).write_bytes(r.stderr)
			assert r.returncode == 0, r.stderr[-2000:]
			tree = probe.syntax(r.stdout.decode()); selected = find(tree, 'function', function); assert len(selected) == 1
			contract = declaration_contract(tree, selected[0])
			assert ['owned-result'] in selected[0] and contract == [['throws', 'Error']]
			rows.append(dict(role=role, argv=argv, exit=r.returncode, seconds=time.monotonic()-start, source_sha256=sha(path), method_C0_AST_sha256=digest(selected[0]), effect_and_method_sha256=digest([contract, selected[0]]), throws_metadata=contract, stdout_sha256=sha(leaf/(name+'-'+role+'.stdout')), limitation='Exact whole-method syntax and declared effect, not whole-method native execution'))
		data = Path(decl['path']).read_bytes(); assert sha(decl['path']) == decl['source_sha256']
		method = data[decl['start']:decl['end']]; assert method.startswith(b'owned FlowGraph flow_graph(') and b'throws Error' in method.split(b'{', 1)[0]
		results[name] = dict(producer=decl, producer_method_sha256=__import__('hashlib').sha256(method).hexdigest(), signature_source=method.split(b'{', 1)[0].decode(), observations=rows)
		(leaf/'result.json').write_text(json.dumps(dict(status='EXACT_METHOD_C0_SYNTAX_ONLY', cohorts=results), indent=2)+'\n')
		print(name, 'exact producer/caller C0 AST and owned throws Error declarations', flush=True)


if __name__ == '__main__':
	main()
