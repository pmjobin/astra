#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compile a read-only observer against the unchanged baseline checker."""
import importlib.util
import argparse
import json
import os
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, COHORTS, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', default='v3'); p.add_argument('--source-root', type=type(ROOT)); a = p.parse_args()
	assert a.version.replace('-', '').isalnum()
	build = BUILD/('diagnosis-'+a.version); leaf = RUNTIME/('diagnosis-'+a.version)
	build.mkdir(exist_ok=False); leaf.mkdir(exist_ok=False)
	spec = importlib.util.spec_from_file_location('base_build', ROOT/'tests/selfhost-typecore/build.py')
	base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
	if a.source_root: base.ROOT = a.source_root.resolve()
	def capture(argv, name, details=None):
		if argv is None:
			(leaf/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n'); return b''
		start = time.monotonic()
		r = subprocess.run(list(map(str, argv)), cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		(leaf/(name+'.json')).write_text(json.dumps(dict(argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic()), indent=2)+'\n')
		print(name, r.returncode, flush=True); assert r.returncode == 0, r.stderr.decode(errors='replace')[:3000]
		return r.stdout
	products = base.build(C0, build, capture, ('O0',), consumer=ROOT/'tests/selfhost-membercall/diagnose.astra', link_inputs=[__file__], product_prefix='diagnose-')
	(leaf/'products.json').write_text(json.dumps(products, indent=2)+'\n')
	initial = read(RUNTIME/'initial.json')
	for name in COHORTS:
		capture([build/'diagnose-O0', *initial['cohorts'][name]['argv'][4:]], name)
		print((leaf/(name+'.stdout')).read_text(), flush=True)


if __name__ == '__main__':
	main()
