#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Collect bounded demand traces and independently recompute exact key equality."""
import argparse
from collections import Counter
import json
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, COHORTS, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args()
	component = BUILD/('diagnostic-'+a.version)/'resource-O0'
	identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources', 'tools') for path, value in identity['identity'][group].items())
	leaf = RUNTIME/('trace-'+a.version); leaf.mkdir(exist_ok=False)
	results = {}
	for name in COHORTS:
		old = read(RUNTIME/'initial/result.json')['cohorts'][name]
		argv = [str(component), *old['argv'][4:]]
		assert all(sha(source) == next(row['sha256'] for row in old['files'] if row['path'] == source) for source in argv[1:])
		start = time.monotonic()
		with (leaf/(name+'.stdout')).open('xb') as out, (leaf/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=ROOT, stdout=out, stderr=err, timeout=180)
		requests = {}; events = []; plans = {}; types = {}; symbols = {}; diagnostics = []; counts = None
		for line in (leaf/(name+'.stdout')).read_text().splitlines():
			words = line.split(); tag = words[0] if words else ''
			if tag == 'GENCOUNTS': counts = list(map(int, words[1:]))
			if tag == 'GENREQUEST':
				request, parent, origin, enclosing, count = map(int, words[1:6]); arguments = tuple(map(int, words[6:6+2*count]))
				assert request not in requests and (parent == 0 or parent in requests)
				requests[request] = dict(parent=parent, origin=origin, enclosing=enclosing, arguments=arguments, span=words[6+2*count:])
			if tag == 'GENEVENT': events.append(list(map(int, words[1:])))
			if tag == 'GENPLAN':
				number, origin, concrete, enclosing, state, nodes, syms, scopes, count = map(int, words[1:10])
				plans[number] = dict(origin=origin, concrete=concrete, enclosing=enclosing, state=state, mapped=[nodes, syms, scopes], arguments=tuple(map(int, words[10:10+2*count])), span=words[10+2*count:])
			if tag == 'GENTYPE': types[int(words[1])] = list(map(int, words[2:]))
			if tag == 'GENSYMBOL': symbols[int(words[1])] = words[2:]
			if tag in ('CHECKED_ERROR', 'ERROR'): diagnostics.append(line)
		assert counts is not None
		# Full structural identity, never a hash or type spelling. Nominals remain
		# exact Binder IDs in this source population, including lexical T owners.
		def type_key(number, depth=0):
			if number == 0: return None
			assert depth <= 128
			kind, nominal, extent, count, *edges = types[number]; assert len(edges) == 2*count
			if nominal: assert nominal in symbols
			return kind, nominal, extent, tuple((type_key(edges[i], depth+1), edges[i+1]) for i in range(0, len(edges), 2))
		def key(row):
			args = row['arguments']
			return row['origin'], type_key(row['enclosing']), tuple((type_key(args[i]), args[i+1]) for i in range(0, len(args), 2))
		plan_keys = [key(row) for row in plans.values()]; assert len(plan_keys) == len(set(plan_keys))
		for request, state, ordinal, *_ in events:
			if state == 2: assert key(requests[request]) == key(plans[ordinal]) and plans[ordinal]['state'] == 2
		keys = [key(row) for row in requests.values()]
		mapped = [sum(row['mapped'][i] for row in plans.values()) for i in range(3)]
		results[name] = dict(argv=argv, exit=r.returncode, start=start, end=time.monotonic(), component_sha256=sha(component), counts=counts, requests=requests, events=events, plans=plans, attempted_prefix=len(requests), distinct_prefix=len(set(keys)), hits=sum(row[1] == 2 for row in events), limits=[row for row in events if row[1] == 5], cycles=[row for row in events if row[1] == 6], mapped=mapped, diagnostics=diagnostics, stdout_sha256=sha(leaf/(name+'.stdout')), ceiling=dict(instances=256, nodes=8000000, symbols=8000000), accounting='map int slots reserved, including zeros; distinct key oracle recursively reconstructs TypeTable edges and exact Binder nominal identities')
		(leaf/'result.json').write_text(json.dumps(results, indent=2)+'\n')
		print(name, 'counts', counts, 'mapped', mapped, 'requests/distinct/hits', len(requests), len(set(keys)), results[name]['hits'], 'limits', results[name]['limits'], flush=True)


if __name__ == '__main__':
	main()
