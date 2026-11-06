#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Recheck immutable original source chains and the separate owner-capture stop."""
import argparse
import json
from pathlib import Path
import time
from state import ROOT, read, sha, bounded_run, population, digest, load_module

BASE = ROOT.parent/'codex/work/astra'
PRIOR = BASE/'runtime/effects25'
RUNTIME = BASE/'runtime/effects25-r1'
BUILD = BASE/'build/effects25-r1'


def first_failure(component, mode):
	leaf = RUNTIME/('first-failure-v1-'+mode); leaf.mkdir(exist_ok=False)
	inputs = read(PRIOR/('cohorts-v1-'+mode+'.json'))['original']['independent_consumer']['argv'][6:]
	argv = [str(component), '--effects-trace', mode, str(leaf/'unused'), *inputs]
	with (leaf/'stdout').open('xb') as out, (leaf/'stderr').open('xb') as err:
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/'time', *argv], cwd=ROOT, stdout=out, stderr=err, timeout=240)
	assert r.returncode == 0
	stops = [line.split()[1:] for line in (leaf/'stdout').read_text().splitlines() if line.startswith('FLOW_VERIFY_STOP ')]
	assert stops and stops[0] == ['55', '26'], stops[:3]
	result = dict(status='FIRST_PREDICATE_REPRODUCED', argv=argv, component_sha256=sha(component), first_stop=stops[0], all_stops=stops, stdout_sha256=sha(leaf/'stdout'), stderr_sha256=sha(leaf/'stderr'), classification='Read-only diagnostic asserts equivalence with the unchanged Flow verifier; no native admission')
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(mode, 'first original Flow failure remains graph 55, predicate 26', flush=True)


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--diagnose-first', action='store_true'); a = p.parse_args()
	if a.diagnose_first: first_failure(a.component, a.mode); return
	leaf = RUNTIME/('cohorts-v1-'+a.mode); leaf.mkdir(exist_ok=False)
	build = BUILD/leaf.name; build.mkdir(exist_ok=False)
	parse = load_module('r1_trace_parser', ROOT/'tests/selfhost-effects/observe.py').parse
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == h for group in ('sources', 'tools') for path, h in identity['identity'][group].items())
	previous = read(PRIOR/('trace-full-v1-'+a.mode)/'result.json'); results = {}
	for name, old in read(PRIOR/('cohorts-v1-'+a.mode+'.json')).items():
		trace = previous[name]; ledger = read(PRIOR/('ledger-v1-'+a.mode+'-'+name)/'ledger.json')
		logical, nodes = population(ledger); assert (digest(logical), digest(nodes)) == (old['population_sha256'], old['node_identity_sha256'])
		for source in ledger['files']:
			data = bytes.fromhex(source['synthetic_source_hex']) if 'synthetic_source_hex' in source else Path(source['path']).read_bytes()
			assert len(data) == source['bytes'] and __import__('hashlib').sha256(data).hexdigest() == source['sha256']
		inputs = old['independent_consumer']['argv'][6:]
		argv = [str(a.component), '--r1-owner-trace', a.mode, str(leaf/'unused'), *inputs]
		start = time.monotonic()
		with (leaf/(name+'.stdout')).open('xb') as out, (leaf/(name+'.stderr')).open('xb') as err:
			r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=ROOT, stdout=out, stderr=err, timeout=240)
		assert r.returncode == 0, (leaf/(name+'.stderr')).read_text()[-2500:]
		tables = parse(leaf/(name+'.stdout'))
		local = next(row for row in tables.get('LOCAL', []) if row[0] == trace['local'][0])
		initializer = next(row for row in tables['INITIALIZER'] if row[0] == trace['initializer'][0])
		local_use = next(row for row in tables['LOCAL_USE'] if row[0] == trace['local_use'][0])
		move = next(row for row in tables['MOVE'] if row[0] == trace['move'][0])
		facts_preserved = (local == trace['local'] and initializer == trace['initializer'] and local_use == trace['local_use'] and move == trace['move'] and tables['CONSUMER'] == trace['consumer'])
		captures = tables.get('R1_OWNER_CAPTURE', [])
		target = build/(name+'.ll'); target.write_bytes(b'R1 original-method negative destination\n'); expected = sha(target)
		native_argv = [str(a.component), '--classstorage-llvm-raw', a.mode, str(target), *inputs]
		with (leaf/(name+'-native.stdout')).open('xb') as out, (leaf/(name+'-native.stderr')).open('xb') as err:
			native = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'-native.time'), *native_argv], cwd=ROOT, stdout=out, stderr=err, timeout=240)
		assert native.returncode != 0 and sha(target) == expected
		results[name] = dict(argv=argv, seconds=time.monotonic()-start, exit=r.returncode, files=len(ledger['files']), nodes=len(nodes), population_sha256=digest(logical), node_identity_sha256=digest(nodes), conditional_facts_preserved=facts_preserved, local=local, local_use=local_use, initializer=initializer, move=move, consumer=tables['CONSUMER'], Flow_status=tables.get('STATUS'), owner_capture_failures=captures, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')), native_attempt=dict(argv=native_argv, exit=native.returncode, destination_preserved=True, stderr_sha256=sha(leaf/(name+'-native.stderr'))), limitation='Original source typing and the unmet owner root; native emission of the complete original methods was attempted and refused upstream; none ran')
		(leaf/'result.json').write_text(json.dumps(results, indent=2)+'\n')
		assert facts_preserved, (name, results[name])
		if name == 'original':
			assert any(row[0:2] == ['55', '2053'] and row[4:8] == ['0', '0', '0', '0'] for row in captures), captures[:4]
		print(a.mode, name, 'conditional facts preserved; Flow owner-capture remains deferred', flush=True)


if __name__ == '__main__':
	main()
