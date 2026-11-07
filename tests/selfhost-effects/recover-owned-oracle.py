#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C0 witnesses for the owner corpus; zero Astra ELF credit."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, bounded_run, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); group = p.add_mutually_exclusive_group(); group.add_argument('--error-owners', action='store_true'); group.add_argument('--loops', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	name = 'recover-loop-qualify' if a.loops else 'recover-error-owned-qualify' if a.error_owners else 'recover-owned-qualify'
	paths = load_module('owned_oracle_paths', ROOT/'tests/selfhost-effects/recover-build.py'); corpus = load_module('owned_oracle_sources', ROOT/('tests/selfhost-effects/'+name+'.py')).corpus()
	leaf = paths.RUNTIME/('owned-oracle-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	def run(argv, name, expected):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == expected, (name, r.stderr[-3000:]); return r
	for name, text in corpus.items():
		source = leaf/(name+'.astra'); source.write_text(text); exe = build/name; inputs = [source, ROOT/'lib/astra/base/errors.astra']; run([C0, '-'+a.mode, *inputs, '-o', exe], name+'-compile', 0); run([exe], name+'-execute', 42)
		ir = run([C0, '-O0', '--dump-llvm', *inputs], name+'-ABI', 0); path = build/(name+'.ll'); path.write_bytes(ir.stdout); run(['opt', '-passes=verify', '-disable-output', path], name+'-verify', 0)
		memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-memory', 42); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
		rows.append(dict(name=name, source_sha256=sha(source), ELF_sha256=sha(exe), ABI_sha256=sha(path), expected_exit=42, unsuppressed_memory='zero errors and live allocations')); print(a.mode, name, 'independent C0 only', flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='C0_ONLY_ORACLE', Astra_ELFs=0, profile=a.mode, C0_sha256=sha(C0), programs=rows), indent=2)+'\n')


if __name__ == '__main__':
	main()
