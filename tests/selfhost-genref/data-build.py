#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the raw AST/Binder observer from explicitly pinned local sources."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args()
	directory = BUILD/('oracle-'+a.version); directory.mkdir(exist_ok=False)
	leaf = RUNTIME/('oracle-build-'+a.version); leaf.mkdir(exist_ok=False); commands = []
	spec = importlib.util.spec_from_file_location('typecore_build', ROOT/'tests/selfhost-typecore/build.py')
	base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
	def capture(argv, name, details=None):
		if argv is None:
			(leaf/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n'); return b''
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=directory, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(name, r.returncode, flush=True); assert r.returncode == 0, r.stderr.decode(errors='replace')[-3000:]; return r.stdout
	products = base.build(C0, directory, capture, ('O0',), consumer=ROOT/'tests/selfhost-genref/data-query.astra', with_flow=True, extra_sources=[ROOT/'tests/selfhost-genref/oracle-data.astra', RUNTIME/'oracle-v1/raw-ast.astra'], product_prefix='genref-data-', link_inputs=[Path(__file__), ROOT/'compiler/syntax/model.json', ROOT/'tests/selfhost-genref/oracle-generate.py'])
	(leaf/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
