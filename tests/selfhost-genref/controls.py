#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh continuity, source refusal, effect, and complete-caller identity checks."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, C0, COHORTS, read, sha, digest


def load(name, path):
	spec = importlib.util.spec_from_file_location(name, path); module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module


def find(tree, tag, name):
	if not isinstance(tree, list): return []
	return ([tree] if tree[:1] == [tag] and ['name', name] in tree else [])+[found for child in tree for found in find(child, tag, name)]


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args()
	leaf = RUNTIME/('controls-'+a.version+'-'+a.mode); leaf.mkdir(exist_ok=False); commands = []; results = {}
	for label in ('source-status', 'layout-lifetime'):
		command = next(row for row in read(PRIOR/'continuity/commands.json') if row['name'] == label+'-'+a.mode); argv = command['argv'].copy(); argv[argv.index('--component')+1] = str(a.component)
		for flag, value in [('--build', BUILD/(leaf.name+'-'+label)), ('--runtime', leaf/label)]: argv[argv.index(flag)+1] = str(value)
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *argv], cwd=ROOT, capture_output=True, timeout=300)
		(leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=label, argv=argv, exit=r.returncode, start=start, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == 0, r.stderr.decode()[-2000:]
		result = read(leaf/label/'result.json'); assert result['status'] == 'PASS'; results[label] = result
		if label == 'source-status': assert read(leaf/label/'observations/result.json')['outcomes'] == {'0':56, '4':12, '3':12}
		print(a.mode, label, 'PASS', flush=True)
		# Reuse unchanged test recipes through their public main functions; route all
		# writes to this campaign. These are explicitly inherited controls.
	for name, arguments in [('negative', ['--component', str(a.component), '--mode', a.mode, '--version', a.version]), ('effect', ['--component', str(a.component), '--version', a.version+'-'+a.mode])]:
		module = load('inherited_'+name, ROOT/('tests/selfhost-callplace/'+name+'.py')); module.RUNTIME = RUNTIME; module.BUILD = BUILD
		before = sys.argv; sys.argv = [str(module.__file__), *arguments]
		try: module.main()
		finally: sys.argv = before
	case = next(row for row in read(PRIOR/'corpus-v6/selection.json') if row['name'] == 'multiple-arguments-order'); assert all(sha(s['path']) == s['sha256'] for s in case['sources'])
	destination = BUILD/(leaf.name+'-preserved.o'); destination.write_bytes(b'preserved inherited model-control destination\n'); destination_sha = sha(destination)
	argv = [str(a.component), '--classstorage-callplace-mutations', a.mode, str(destination), *[s['path'] for s in case['sources']]]; start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/'downstream-models.time', *argv], cwd=BUILD, capture_output=True, timeout=180)
	(leaf/'downstream-models.stdout').write_bytes(r.stdout); (leaf/'downstream-models.stderr').write_bytes(r.stderr); assert r.returncode == 0 and sha(destination) == destination_sha
	mutations = [line.split() for line in r.stdout.decode().splitlines() if line.startswith('CALLPLACE_MODEL_MUTATION ')]; assert len(mutations) == 28 and all(row[-1] == 'VALID_RESTORED' for row in mutations)
	commands.append(dict(name='downstream-models', argv=argv, exit=r.returncode, start=start, end=time.monotonic())); results['inherited_downstream_models'] = dict(categories=28, source=case['sources'], preserved_destination_sha256=destination_sha, attribution='Inherited Generic/Core/CFG/SSA controls freshly replayed; excluded from GENREF new mutation counts')
	probe = load('C0_syntax', ROOT/'tests/selfhost-classstorage/abi-probe.py'); original = read(RUNTIME.parent/'membercall22/facts-v2/result.json')['cohorts']; callers = {}
	for name in COHORTS:
		old = original[name]; caller = old['enclosing_function']; path = Path(old['first_stop']['path']); raw = path.read_bytes()[caller['start']:caller['end']]
		assert b'throws Error' in raw.split(b'{', 1)[0] and hashlib.sha256(raw).hexdigest() == old['enclosing_bytes_sha256']
		argv = [str(C0), '--dump-syntax', str(path)]; start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'-caller.time'), *argv], cwd=BUILD, capture_output=True, timeout=60)
		(leaf/(name+'-caller.stdout')).write_bytes(r.stdout); (leaf/(name+'-caller.stderr')).write_bytes(r.stderr); assert r.returncode == 0
		selected = find(probe.syntax(r.stdout.decode()), 'function', caller['name']); assert len(selected) == 1 and digest(selected[0]) == old['enclosing_AST_sha256']
		commands.append(dict(name=name+'-caller', argv=argv, exit=r.returncode, start=start, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		callers[name] = dict(path=str(path), caller=caller, bytes_sha256=old['enclosing_bytes_sha256'], C0_AST_sha256=digest(selected[0]), original_call_node=old['call_node']['node'], native_status='DEFERRED: complete throws Error caller; no recoverable exception/error ABI authorized')
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, component_sha256=sha(a.component), continuity=results, original_callers=callers, commands=commands, original_statuses={'admitted':56, 'rejected':12, 'deferred':12}, scope='Existing negatives/effect boundary and original complete-caller ASTs. The throwing callers are not new native application qualifications.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
