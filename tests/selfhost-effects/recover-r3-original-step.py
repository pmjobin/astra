#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused before/after attempt on the identical original input paths/bytes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r3_original_step_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('original-step-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	before = read(paths.RUNTIME/'original-before-O0/result.json'); inputs = [Path(row['path']) for row in before['inputs']]; assert all(sha(row['path']) == row['sha256'] for row in before['inputs']); assert sha(inputs[0]) == '8641d4ff6a1f19cc8bfc0ccbec492a8f7d4248eebcb05373c15479e7114a3e68'
	def run(argv, name, allowed):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stdout[-2500:], r.stderr[-2500:]); return r
	target = build/'Astra.ll'; target.write_text('Original unchanged input sentinel\n'); sentinel = sha(target); native = run([a.component, '--native', target, *inputs], 'Astra-attempt', range(9)); emitted = native.returncode == 0; boundary = None
	if emitted:
		run(['opt', '-passes=verify', '-disable-output', target], 'LLVM-verify', (0,)); optimized = build/'optimized.ll'; run(['opt', '-passes=default<'+a.mode+'>', '-S', target, '-o', optimized], 'LLVM-optimize', (0,)); obj = build/'Astra.o'; exe = build/'Astra'; run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], 'Astra-object', (0,)); libraries = load_module('r3_original_providers', ROOT/'tests/selfhost-typecore/build.py'); run(['cc', '-no-pie', obj, *[a.component.parent/(name+'.o') for name in libraries.PROVIDERS], '-o', exe], 'Astra-link', (0,)); run([exe], 'Astra-execute', (42,)); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], 'Astra-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
	else:
		assert sha(target) == sentinel
		match = re.search(rb'RECOVER_FLOW ([0-9]+) ([0-9]+) ([0-9]+)', native.stdout)
		if match and int(match[2]) > 0:
			ledger = paths.RUNTIME/'original-before-O0/Astra-original-boundary-ledger.stdout'
			for line in ledger.read_text().splitlines():
				row = line.split()
				if len(row) == 10 and row[0] == 'NODE' and int(row[1]) == int(match[2]):
					path = Path(bytes.fromhex(row[7]).decode()); data = path.read_bytes(); first, last = int(row[8]), int(row[9]); assert path in inputs and 0 <= first <= last <= len(data); fragment = data[first:last]; boundary = dict(stage=int(match[1]), node=int(match[2]), syntax_kind=int(row[2]), source=str(path), source_sha256=sha(path), start_byte=first, end_byte=last, fragment_sha256=hashlib.sha256(fragment).hexdigest(), first_line=fragment.decode().splitlines()[0], mapping='Freshly reproduced predecessor parser ledger on identical source paths and hashes', ledger_sha256=sha(ledger))
			assert boundary
	result = dict(status='ORIGINAL_FUNCTION_NATIVE_EXECUTED' if emitted else 'EXACT_NEXT_ORIGINAL_SOURCE_BOUNDARY', profile=a.mode, component_sha256=sha(a.component), inputs=before['inputs'], function=before['source'], Astra_emitted=emitted, Astra_actual_execution=42 if emitted else None, output=native.stdout.decode(), first_source_boundary=boundary, destination_preserved=not emitted, limitation='The focused compiler shares the existing parser and identical original inputs. Final whole-compiler source-ledger replay remains separate; a source-bound deferral earns no Astra execution credit.')
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n'); print(json.dumps(result, indent=2), flush=True)


if __name__ == '__main__':
	main()
