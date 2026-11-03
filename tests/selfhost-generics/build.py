#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the independently usable specialization/Flow consumer out of source."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	a.runtime.mkdir(parents=True, exist_ok=False)
	spec = importlib.util.spec_from_file_location('typecore_build', ROOT/'tests/selfhost-typecore/build.py')
	base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
	def capture(argv, name, details=None):
		if argv is None:
			(a.runtime/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n'); return b''
		start = time.monotonic()
		r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		(a.runtime/(name+'.json')).write_text(json.dumps(dict(argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()), indent=2)+'\n')
		print(name, r.returncode, flush=True)
		assert r.returncode == 0, r.stderr.decode(errors='replace')[:3000]
		return r.stdout
	products = base.build(a.compiler.resolve(), a.build.resolve(), capture, ('O0',), with_flow=True, consumer=Path(__file__).with_name('query.astra'), product_prefix='astra-generics-', extra_sources=[Path(__file__).with_name('mutations.astra')])
	(a.runtime/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
