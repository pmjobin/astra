#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read-only C0 design witnesses; these do not qualify the self-hosted compiler."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time
from state import bounded_run, ROOT, RUNTIME, BUILD, C0, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args()
	leaf = RUNTIME/('c0-design-'+a.version); leaf.mkdir(exist_ok=False)
	build = BUILD/('c0-design-'+a.version); build.mkdir(exist_ok=False)
	rows = []
	def run(argv, name, expected=0):
		start = time.monotonic(); r = bounded_run(list(map(str, argv)), cwd=build, capture_output=True, timeout=120)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, expected=expected, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(rows, indent=2)+'\n')
		assert r.returncode == expected, r.stderr[-3000:]
		return r
	results = []
	for mode in ('O0', 'O2'):
		for name in ('heap-factories', 'argument-abort', 'success-groups'):
			source = ROOT/'tests/error-1/fixtures'/(name+'.astra'); exe = build/(name+'-'+mode)
			run([C0, '-'+mode, source, '-o', exe], name+'-'+mode+'-build')
			run([exe], name+'-'+mode+'-execute', 42)
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-'+mode+'-memory', 42)
			assert b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
			ir = run([C0, '-'+mode, '--dump-llvm', source], name+'-'+mode+'-llvm').stdout
			irpath = build/(name+'-'+mode+'.ll'); irpath.write_bytes(ir)
			run(['llvm-as', irpath, '-o', build/(name+'-'+mode+'.bc')], name+'-'+mode+'-assemble')
			run(['opt', '-passes=verify', '-disable-output', irpath], name+'-'+mode+'-verify')
			checked = [line.decode() for line in ir.splitlines() if line.startswith(b'define internal fastcc ptr ') and b'%success.storage' in line]
			if mode == 'O0': assert checked, ir[:1000]
			results.append(dict(source=str(source), source_sha256=sha(source), mode=mode, executable_sha256=sha(exe), llvm_sha256=sha(irpath), checked_entry_definitions=checked, exit=42, Valgrind='zero errors, zero live blocks, zero suppressions'))
			# A parser refusal is an explicit existing C0 limitation, never an effect test.
	finally_source = leaf/'finally.astra'; finally_source.write_text('int main() { try { return 42; } finally { } }\n')
	r = run([C0, '--dump-syntax', finally_source], 'finally-parser', 1)
	assert b'finally' in r.stderr or b'catch' in r.stderr
	(leaf/'result.json').write_text(json.dumps(dict(status='C0_DESIGN_EVIDENCE_ONLY', C0_sha256=sha(C0), programs=results, finally_boundary=dict(source_sha256=sha(finally_source), exit=r.returncode, stderr=r.stderr.decode()), selfhost_qualification=False), indent=2)+'\n')
	print('Six C0 O0/O2 native/memory/LLVM design witnesses; finally parser boundary retained', flush=True)


if __name__ == '__main__':
	main()
