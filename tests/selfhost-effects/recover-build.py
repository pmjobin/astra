#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Completion builds in a new external leaf; never replace R2 checkpoints."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, C0, load_module, bounded_run, sha

BASE = ROOT.parent/'codex/work/astra'
BUILD = BASE/'build/effects25-r2-completion'
RUNTIME = BASE/'runtime/effects25-r2-completion'


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--check', action='store_true'); p.add_argument('--core-check', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	build = BUILD/(a.version+'-'+a.mode); build.mkdir(parents=True, exist_ok=True)
	leaf = RUNTIME/('build-'+a.version+'-'+a.mode)/str(time.time_ns()); leaf.mkdir(parents=True)
	commands = []
	def capture(argv, name, details=None):
		if argv is None:
			(leaf/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n'); return b''
		argv = list(map(str, argv))
		if (a.check or a.core_check) and name.startswith('typecore-'):
			argv = [*argv[:3], '--dump-core' if a.core_check else '--check', *argv[4:argv.index('--link-object')]]
		start = time.monotonic(); r = bounded_run(argv, cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=3600)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(name, r.returncode, flush=True); assert r.returncode == 0, r.stderr.split(b'Command being timed')[0][-6000:]
		if (a.check or a.core_check) and name.startswith('typecore-'): raise SystemExit(0)
		return r.stdout
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split(); shim = build/'llvm-capi.o'
	capture(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', ROOT/'compiler/backend/llvm/capi.c', '-o', shim], 'llvm-capi')
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis', 'native'], text=True).strip(); assert library.startswith('-l') and ' ' not in library
	base = load_module('recover_type_build', ROOT/'tests/selfhost-typecore/build.py')
	extra = [ROOT/'compiler/backend/llvm/capi.astra', ROOT/'compiler/backend/llvm/effect-abi.astra', *sorted((ROOT/'compiler/core').glob('recover*.astra')), *sorted((ROOT/'compiler/cfg').glob('recover-*.astra')), *sorted((ROOT/'compiler/ssa').glob('recover*.astra')), *sorted((ROOT/'compiler/backend/llvm').glob('recover-*.astra')), ROOT/'tests/selfhost-effects/recover-mutations.astra', ROOT/'tests/selfhost-effects/recover-owner-mutations.astra', ROOT/'tests/selfhost-effects/recover-loop-mutations.astra', ROOT/'tests/selfhost-effects/recover-r4-mutations.astra', ROOT/'tests/selfhost-effects/recover-r4-observe.astra']
	products = base.build(C0, build, capture, (a.mode,), consumer=ROOT/'tests/selfhost-effects/recover-query.astra', extra_sources=extra, product_prefix='astra-recover-', link_objects=[shim], link_libraries=[library[2:]], link_inputs=[Path(__file__)])
	(leaf/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
