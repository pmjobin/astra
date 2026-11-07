#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare actual fatal receiver ordering, without returning-path credit."""
import argparse
import json
import os
from pathlib import Path
import resource
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def no_core():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r3_receiver_guard_paths', ROOT/'tests/selfhost-effects/recover-build.py'); oracle = load_module('r3_receiver_guard_sources', ROOT/'tests/selfhost-effects/recover-r3-source-oracles.py'); leaf = paths.RUNTIME/('r3-receiver-guard-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, name, expected=0):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(argv, cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), preexec_fn=no_core, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == expected, (name, r.returncode, r.stdout[-1500:], r.stderr[-2000:]); return r
	for name in ('null-checked-receiver', 'null-receiver-later-error'):
		source = leaf/(name+'.astra'); source.write_text(oracle.corpus()[name]); inputs = [source, ROOT/'lib/astra/base/errors.astra']; c0 = build/(name+'-C0'); run([C0, '-'+a.mode, *inputs, '-o', c0], name+'-C0-build'); run([c0], name+'-C0-fatal', -4)
		ir = build/(name+'.ll'); run([a.component, '--native', ir, *inputs], name+'-Astra-emit'); run(['opt', '-passes=verify', '-disable-output', ir], name+'-verify'); optimized = build/(name+'-optimized.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', ir, '-o', optimized], name+'-optimize'); run(['opt', '-passes=verify', '-disable-output', optimized], name+'-optimized-verify'); obj = build/(name+'.o'); exe = build/(name+'-Astra'); run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], name+'-object'); run(['cc', '-no-pie', obj, '-o', exe], name+'-link'); run([exe], name+'-Astra-fatal', -4)
		rows.append(dict(name=name, source_sha256=sha(source), Astra_raw_LLVM_sha256=sha(ir), Astra_ELF_sha256=sha(exe), C0_ELF_sha256=sha(c0), Astra_exit=-4, C0_exit=-4)); print(a.mode, name, 'C0/Astra SIGILL before recoverable argument error', flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='FATAL_CHECKED_RECEIVER_ORDER', profile=a.mode, component_sha256=sha(a.component), programs=rows, returning_effect_program_credit=0, limitation='Actual fatal child signals; no returning Valgrind or fatal-unwind claim. Core dumps disabled. Separate physical mutations verify guard direction and argument ordering.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
