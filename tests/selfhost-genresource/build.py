#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build a source-bound diagnostic consumer using the established recipe."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, BUILD, RUNTIME, C0


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--source-root', type=Path); a = p.parse_args()
	assert a.version.replace('-', '').isalnum()
	build = BUILD/('diagnostic-'+a.version); leaf = RUNTIME/('diagnostic-'+a.version)
	build.mkdir(parents=True, exist_ok=False); leaf.mkdir(parents=True, exist_ok=False)
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
	products = base.build(C0, build, capture, ('O0',), consumer=base.ROOT/'tests/selfhost-genresource/query.astra', link_inputs=[ROOT/'tests/selfhost-typecore/build.py', __file__], product_prefix='resource-')
	(leaf/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
