#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused Typecore build; explicit external outputs and process-group deadlines."""
import argparse
import json
import os
import time
from state import ROOT, C0, load_module, bounded_run, sha
from pathlib import Path

BASE = ROOT.parent/'codex/work/astra'


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	build = BASE/'build/effects25-r1'/('typecore-'+a.version+'-'+a.mode); build.mkdir(parents=True, exist_ok=True)
	leaf = BASE/'runtime/effects25-r1'/('typecore-build-'+a.version+'-'+a.mode); leaf.mkdir(exist_ok=False); commands = []
	base = load_module('r1_typecore_build', ROOT/'tests/selfhost-typecore/build.py')
	def capture(argv, name, details=None):
		if argv is None:
			(leaf/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n'); return b''
		start = time.monotonic()
		r = bounded_run(list(map(str, argv)), cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=900)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(name, r.returncode, flush=True); assert r.returncode == 0, r.stderr[-4000:]; return r.stdout
	products = base.build(C0, build, capture, (a.mode,), consumer=ROOT/'tests/selfhost-effects/r1-typecore.astra', product_prefix='r1-typecore-', link_inputs=[Path(__file__)])
	(leaf/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
