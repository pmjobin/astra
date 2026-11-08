#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay all frozen source/node cohorts with disclosed read-only relocation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, load_module, read, sha, digest, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); p.add_argument('--historical', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r5_cohort_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('cohorts-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
	for group in ('sources', 'tools'):
		for path, expected in identity['identity'][group].items():
			if a.historical and group == 'sources' and Path(path).is_relative_to(ROOT):
				data = subprocess.check_output(['git', 'show', 'c271e0822d0fc12a878a5adc1388aa1a8e147067:'+str(Path(path).relative_to(ROOT))], cwd=ROOT); assert hashlib.sha256(data).hexdigest() == expected
			else: assert sha(path) == expected
	history = paths.RUNTIME/'r4-history'; old = read(history/('runtime/regression-final16-'+a.mode+'/cohorts-v1-'+a.mode+'/result.json')); parse = load_module('r5_cohort_parser', ROOT/'tests/selfhost-effects/observe.py').parse; commands = []; results = {}
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stderr[-2000:]); return r
	for name, prior in old.items():
		root = history/'frozen'/name; files = {str(p.relative_to(root)): p for p in root.rglob('*') if p.is_file()}; inputs = []; relative = {}; logical = {}; relocations = []
		for original in prior['argv'][4:]:
			matches = [key for key in files if original.endswith('/'+key)]; assert len(matches) == 1, original
			key = matches[0]; source = files[key]; inputs.append(source); relative[str(source)] = key; logical[key] = (source.stat().st_size, sha(source)); relocations.append(dict(original=original, actual=str(source), sha256=sha(source)))
		assert len(inputs) == prior['files'] - 1
		ledger = run([a.component, '--classstorage-source-ledger', a.mode, build/'unused', *inputs], name+'-ledger', range(9)); nodes = []; typed = {}
		for line in ledger.stdout.splitlines():
			r = line.split()
			if not r: continue
			if r[0] == b'SOURCE':
				path = bytes.fromhex(r[1].decode()).decode(); raw = bytes(map(int, r[2:])); assert path == '<Utf8MessageFactory>' and files[path].read_bytes() == raw
				relative[path] = path; logical[path] = (len(raw), hashlib.sha256(raw).hexdigest())
			if r[0] == b'NODE':
				path = bytes.fromhex(r[7].decode()).decode(); key = relative[path]; nodes.append([int(r[1]), int(r[2]), key, int(r[8]), int(r[9]), logical[key][1]]); typed[int(r[1])] = tuple(map(int, r[4:7]))
		assert len(logical) == prior['files'] and len(nodes) == prior['nodes'] and digest(logical) == prior['population_sha256'] and digest(nodes) == prior['node_identity_sha256']
		run([a.component, '--r1-owner-trace', a.mode, build/'unused', *inputs], name+'-trace'); tables = parse(leaf/(name+'-trace.stdout'))
		for key, table in [('local', 'LOCAL'), ('local_use', 'LOCAL_USE'), ('initializer', 'INITIALIZER'), ('move', 'MOVE')]:
			assert next(row for row in tables[table] if row[0] == prior[key][0]) == prior[key]
		assert tables['CONSUMER'] == prior['consumer']
		for key, deferred in [('local_use', 17), ('initializer', 17), ('move', 19)]: assert typed[int(prior[key][0])] == (int(prior[key][1]), 4, deferred)
		target = build/(name+'.ll'); target.write_text('Frozen original population sentinel\n'); sentinel = sha(target); refusal = run([a.component, '--classstorage-llvm-raw', a.mode, target, *inputs], name+'-native-refusal', range(1, 9)); assert sha(target) == sentinel
		root_proof = None
		if name == 'original':
			run([a.component, '--effects-trace', a.mode, build/'unused', *inputs], name+'-predicate'); stops = [r.split()[1:] for r in (leaf/(name+'-predicate.stdout')).read_text().splitlines() if r.startswith('FLOW_VERIFY_STOP ')]; assert stops and stops[0] == ['55', '26']
			captures = tables.get('R1_OWNER_CAPTURE', []); assert any(row[:2] == ['55', '2053'] and row[4:8] == ['0', '0', '0', '0'] for row in captures); root_proof = dict(status='DEFERRED', graph=55, symbol=2053, predicate=26, source_root=0, grown_slot=6, first_stop=stops[0])
		results[name] = dict(files=len(logical), explicit_inputs=len(inputs), nodes=len(nodes), population_sha256=digest(logical), node_identity_sha256=digest(nodes), conditional_17_19_preserved=True, trace_sha256=sha(leaf/(name+'-trace.stdout')), source_ledger_sha256=sha(leaf/(name+'-ledger.stdout')), native_refusal_exit=refusal.returncode, sentinel_preserved=True, relocations=relocations, independent_root=root_proof)
		(leaf/'result.json').write_text(json.dumps(dict(status='FROZEN_SOURCE_NODE_COHORTS_REPLAYED', profile=a.mode, component_sha256=sha(a.component), historical_compiler=a.historical, cohorts=results, Astra_native_credit=0, limitation='Original source bytes, node IDs, syntax kinds, logical filenames, spans and synthetic builtin bytes match their frozen hashes. Temporary physical paths are explicitly relocated. Native refusal is preserved; predicate26 remains independently DEFERRED.'), indent=2)+'\n'); print(a.mode, name, 'exact frozen nodes/facts and refusal reproduced', flush=True)


if __name__ == '__main__':
	main()
