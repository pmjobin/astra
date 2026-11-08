#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Measure source-bound signed literal forms and preserve any actual refusal."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

CASES = {
	'negative-literal': 'int main() { int value = -42; return -value; }\n',
	'min-literal': 'int identity(int value) { return +value; } int main() { if (identity(-2147483648) == 0 - 2147483647 - 1) return 42; return 3; }\n',
	'small-min-literal': 'i8 inverse(i8 value) { return -value; } int main() { i8 value = -128; if (inverse(value) == value) return 42; return 3; }\n',
}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r5_literal_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('prefix-literals-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stderr[-2000:]); return r
	for name, text in CASES.items():
		source = leaf/(name+'.astra'); source.write_text(text); inputs = [source, ROOT/'lib/astra/base/errors.astra']; c0 = build/name; run([C0, '-'+a.mode, *inputs, '-o', c0], name+'-C0-build'); run([c0], name+'-C0-execute', (42,)); target = build/(name+'.ll'); target.write_text('Unqualified signed literal sentinel\n'); before = sha(target); native = run([a.component, '--native', target, *inputs], name+'-Astra', range(9)); emitted = native.returncode == 0
		if emitted:
			run(['opt', '-passes=verify', '-disable-output', target], name+'-verify'); optimized = build/(name+'-optimized.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', target, '-o', optimized], name+'-optimize'); run(['opt', '-passes=verify', '-disable-output', optimized], name+'-optimized-verify'); obj = build/(name+'.o'); exe = build/(name+'-Astra'); run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], name+'-object'); run(['cc', '-no-pie', obj, '-o', exe], name+'-link'); actual = run([exe], name+'-Astra-execute', (42,))
			for label, binary in [('Astra', exe), ('C0', c0)]:
				memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', binary], name+'-'+label+'-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr and memory.stdout == actual.stdout
		else:
			assert sha(target) == before
		ledger = run([a.component, '--classstorage-source-ledger', a.mode, build/'unused', *inputs], name+'-source-ledger', range(9)); nodes = []
		for line in ledger.stdout.splitlines():
			r = line.split()
			if r and r[0] == b'NODE' and bytes.fromhex(r[7].decode()).decode() == str(source): nodes.append(dict(node=int(r[1]), kind=int(r[2]), type=int(r[4]), flags=int(r[5]), deferred=int(r[6]), start=int(r[8]), end=int(r[9])))
		rows.append(dict(name=name, source_sha256=sha(source), C0_exit=42, C0_ELF_sha256=sha(c0), Astra_emitted=emitted, Astra_exit=native.returncode, Astra_execution=42 if emitted else None, Astra_LLVM_sha256=sha(target) if emitted else None, Astra_ELF_sha256=sha(exe) if emitted else None, stdout=native.stdout.decode(), destination_preserved=not emitted, source_nodes=nodes))
	(leaf/'result.json').write_text(json.dumps(dict(status='ACTUAL_SIGNED_LITERAL_FORMS' if all(row['Astra_emitted'] for row in rows) else 'SIGNED_LITERAL_FORMS_PARTIAL', profile=a.mode, component_sha256=sha(a.component), programs=rows, Astra_native_executions=sum(row['Astra_emitted'] for row in rows), limitation='Only successful matched-profile LLVM to ELF executions with independent C0 and unsuppressed returning memory receive execution credit. Refusals preserve destinations and source-node facts. Typecore magnitude facts remain original; a source-bound RecoverTypes parent relation must be independently verified before emission.'), indent=2)+'\n'); print(a.mode, sum(row['Astra_emitted'] for row in rows), 'of 3 signed literal forms actually executed by Astra', flush=True)


if __name__ == '__main__':
	main()
