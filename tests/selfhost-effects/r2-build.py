#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""R2 physical ABI probe and complete compiler, with explicit external outputs."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, C0, load_module, bounded_run, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--focused', action='store_true'); p.add_argument('--check', action='store_true'); a = p.parse_args()
	state = load_module('r2_build_state', ROOT/'tests/selfhost-effects/r2-state.py')
	if a.focused:
		build = state.BUILD/('abi-'+a.mode); build.mkdir(exist_ok=True)
		leaf = state.RUNTIME/('abi-build-'+a.mode)/str(time.time_ns()); leaf.mkdir(parents=True)
		text = (ROOT/'tests/selfhost-effects/r2-abi.astra').read_text().replace('int r2_abi_cli(string[] args)', 'int main(string[] args)')
		consumer = state.RUNTIME/('abi-main-'+__import__('hashlib').sha256(text.encode()).hexdigest()+'.astra')
		if consumer.exists(): assert consumer.read_text() == text
		else: consumer.write_text(text)
		commands = []
		def capture(argv, name, details=None):
			if argv is None:
				(leaf/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n'); return b''
			argv = list(map(str, argv))
			if a.check and name.startswith(('ownflow-', 'typecore-')):
				argv = [*argv[:3], '--check', *argv[4:argv.index('--link-object')]]
			start = time.monotonic(); r = bounded_run(argv, cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=1800)
			(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
			commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
			(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
			print(name, r.returncode, flush=True); assert r.returncode == 0, r.stderr.split(b'Command being timed')[0][-5000:]
			if a.check and name.startswith(('ownflow-', 'typecore-')): raise SystemExit(0)
			return r.stdout
		assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
		flags = subprocess.check_output(['llvm-config', '--cflags'], text=True).split()
		shim = build/'llvm-capi.o'; capture(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *flags, '-c', ROOT/'compiler/backend/llvm/capi.c', '-o', shim], 'llvm-capi')
		library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'analysis', 'native'], text=True).strip(); assert library.startswith('-l') and ' ' not in library
		base = load_module('r2_probe_build', ROOT/'tests/selfhost-typecore/build.py')
		products = base.build(C0, build, capture, (a.mode,), consumer=consumer, extra_sources=[ROOT/'compiler/backend/llvm/capi.astra', ROOT/'compiler/backend/llvm/effect-abi.astra'], product_prefix='abi-', link_objects=[shim], link_libraries=[library[2:]], link_inputs=[Path(__file__), ROOT/'tests/selfhost-effects/r2-abi.astra'])
		(leaf/'products.json').write_text(json.dumps(products, indent=2)+'\n'); return
	full = load_module('r2_full_inputs', ROOT/'tests/selfhost-effects/full-build.py')
	full.RUNTIME = state.RUNTIME; full.BUILD = state.BUILD; full.INPUTS = state.RUNTIME/'compiler-inputs'; full.prepare()
	typecore = (ROOT/'tests/selfhost-effects/r1-typecore.astra').read_text().replace('int main(string[] args)', 'int r1_typecore_cli(string[] args)').replace('args[1] == "--mutations"', 'args[1] == "--r1-type-mutations"')
	view = full.INPUTS/'r1-typecore.astra'
	if view.exists(): assert view.read_text() == typecore
	else: view.write_text(typecore)
	genref = load_module('r2_genref_build', ROOT/'tests/selfhost-genref/build.py'); genref.RUNTIME = full.INPUTS
	original = genref.original
	def extend(*args, **kwargs):
		kwargs['consumer'] = ROOT/'tests/selfhost-effects/r2-query.astra'
		kwargs['extra_sources'] = [*kwargs['extra_sources'], full.INPUTS/'genref-query.astra', full.INPUTS/'flow-diagnostic.astra', full.INPUTS/'effects-observe.astra', view, ROOT/'tests/selfhost-effects/source.astra', ROOT/'tests/selfhost-effects/r1-owner.astra', ROOT/'tests/selfhost-effects/r2-abi.astra']
		kwargs['link_inputs'] = [*kwargs['link_inputs'], Path(__file__), ROOT/'tests/selfhost-effects/observe.astra', ROOT/'tests/selfhost-effects/r1-typecore.astra']
		return original(*args, **kwargs)
	genref.original = extend; genref.base.core.base.build = genref.build
	genref.base.subprocess = __import__('types').SimpleNamespace(**vars(genref.base.subprocess))
	def run(argv, **kwargs):
		kwargs.setdefault('timeout', 3600); return bounded_run(argv, **kwargs)
	genref.base.subprocess.run = run
	sys.argv = [sys.argv[0], '--compiler', str(C0), '--build', str(state.BUILD/('compiler-v1-'+a.mode)), '--runtime', str(state.RUNTIME/('compiler-build-v1-'+a.mode)), '--mode', a.mode]
	if a.check: sys.argv += ['--semantic-only']
	genref.base.main()


if __name__ == '__main__':
	main()
