#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Matched original ledgers and the separate post-type-repair Flow consumer."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import bounded_run, ROOT, RUNTIME, BUILD, PRIOR, INPUT, COHORTS, read, sha, digest, population


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args()
	results = {}; original_calls = (40833, 42968, 46736, 47584)
	for name, call in zip(COHORTS, original_calls):
		old_row = read(INPUT/('reference/report/GENREF24-COHORTS-'+a.mode+'.json'))[name]; old = read(PRIOR/('ledger-v3-'+a.mode+'-'+name)/'ledger.json')
		leaf = RUNTIME/('ledger-'+a.version+'-'+a.mode+'-'+name); directory = BUILD/leaf.name; argv = old_row['collector']['argv'].copy()
		for flag, value in [('--component', a.component), ('--build', directory), ('--runtime', leaf)]: argv[argv.index(flag)+1] = str(value)
		start = time.monotonic(); r = bounded_run(argv, cwd=ROOT, capture_output=True, timeout=300)
		assert r.returncode == 0, r.stderr[-3000:]
		(leaf/'collector.stdout').write_bytes(r.stdout); (leaf/'collector.stderr').write_bytes(r.stderr)
		new = read(leaf/'ledger.json'); logical, nodes = population(new); assert (logical, nodes) == population(old)
		assert digest(logical) == old_row['population_sha256'] and digest(nodes) == old_row['node_identity_sha256']
		fact = next(row for row in new['nodes'] if row['node'] == call); assert (fact['type'], fact['flags'], fact['deferred']) == (1, 0, 19)
		consumer_argv = read(leaf/'commands.json')[0]['argv'].copy(); consumer_argv[consumer_argv.index('--classstorage-source-ledger')] = '--classstorage-admit'
		r = bounded_run(consumer_argv, cwd=ROOT, capture_output=True, timeout=240)
		(leaf/'consumer.stdout').write_bytes(r.stdout); (leaf/'consumer.stderr').write_bytes(r.stderr)
		codes = [line for line in r.stderr.decode().splitlines() if line.startswith('CHECKED_CONSUMER')]
		assert r.returncode != 0 and codes == [], (name, r.returncode, codes)
		status = next(line for line in r.stdout.decode().splitlines() if line.startswith('STATUS ')); assert status.split()[1] != '0'
		results[name] = dict(files=len(new['files']), nodes=len(nodes), population_sha256=digest(logical), node_identity_sha256=digest(nodes), original_call=fact, component_sha256=sha(a.component), ledger_sha256=sha(leaf/'ledger.json'), independent_consumer=dict(argv=consumer_argv, exit=r.returncode, status=status, codes=codes), seconds=time.monotonic()-start, limitation='Generic type checks no longer stop at 25; complete Flow admission still fails. Obligation 19 is not discharged and no original throwing caller executes.')
		(RUNTIME/('cohorts-'+a.version+'-'+a.mode+'.json')).write_text(json.dumps(results, indent=2)+'\n'); print(a.mode, name, status, 'original obligation 19 retained', flush=True)


if __name__ == '__main__':
	main()
