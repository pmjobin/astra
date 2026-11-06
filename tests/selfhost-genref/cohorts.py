#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh matched lexical ledgers and genuinely separate whole-source consumers."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, COHORTS, read, sha, digest, population


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args()
	results = {}; original_calls = (40833, 42968, 46736, 47584)
	for name, call in zip(COHORTS, original_calls):
		prior = read(PRIOR/'cohorts-v2.json')[name]; old = read(PRIOR/('ledger-v2-'+name)/'ledger.json')
		leaf = RUNTIME/('ledger-'+a.version+'-'+a.mode+'-'+name); directory = BUILD/leaf.name; argv = prior['argv'].copy()
		for flag, value in [('--component', a.component), ('--build', directory), ('--runtime', leaf)]: argv[argv.index(flag)+1] = str(value)
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', RUNTIME/(leaf.name+'.time'), *argv], cwd=ROOT, capture_output=True, timeout=300)
		assert r.returncode == 0, r.stderr.decode()[-2000:]
		(leaf/'collector.stdout').write_bytes(r.stdout); (leaf/'collector.stderr').write_bytes(r.stderr)
		new = read(leaf/'ledger.json'); logical, nodes = population(old); assert (logical, nodes) == population(new)
		assert digest(logical) == prior['population_sha256'] and digest(nodes) == prior['node_identity_sha256']
		fact = next(row for row in new['nodes'] if row['node'] == call); assert (fact['type'], fact['flags'], fact['deferred']) == (1, 0, 19), (name, fact)
		consumer_argv = read(leaf/'commands.json')[0]['argv'].copy(); consumer_argv[consumer_argv.index('--classstorage-source-ledger')] = '--classstorage-admit'
		consumer_start = time.monotonic(); consumer = subprocess.run(consumer_argv, cwd=ROOT, capture_output=True, timeout=240)
		(leaf/'consumer.stdout').write_bytes(consumer.stdout); (leaf/'consumer.stderr').write_bytes(consumer.stderr)
		codes = [line for line in consumer.stderr.decode().splitlines() if line.startswith('CHECKED_CONSUMER')]
		assert consumer.returncode == 2 and codes == ['CHECKED_CONSUMER 1 25'], (name, codes)
		results[name] = dict(files=len(new['files']), nodes=len(nodes), population_sha256=digest(logical), node_identity_sha256=digest(nodes), component_sha256=sha(a.component), typed_before=sum(bool(row['type']) and row['deferred'] == 0 for row in old['nodes']), typed_after=sum(bool(row['type']) and row['deferred'] == 0 for row in new['nodes']), original_call=fact, old_ledger_sha256=sha(PRIOR/('ledger-v2-'+name)/'ledger.json'), new_ledger_sha256=sha(leaf/'ledger.json'), first_lexical_diagnostic=new['diagnostics'][0] if new['diagnostics'] else None, collector=dict(argv=argv, exit=r.returncode, start=start, end=consumer_start), independent_consumer=dict(argv=consumer_argv, exit=consumer.returncode, start=consumer_start, end=time.monotonic(), codes=codes), limitation='The independent reference gate advances from 7 to separate call verification 25. Original ownership/borrow obligation 19 remains. Whole modules and complete throwing callers remain refused; no Stage 1 claim.')
		(RUNTIME/('cohorts-'+a.version+'-'+a.mode+'.json')).write_text(json.dumps(results, indent=2)+'\n'); print(a.mode, name, codes, 'original call obligation 19 retained', flush=True)


if __name__ == '__main__':
	main()
