#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Extend the Core exact-product recipe; never build in the source tree."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('core_build', ROOT/'tests/selfhost-coreir/build.py')
core = importlib.util.module_from_spec(spec)
spec.loader.exec_module(core)


def sources():
	return [*sorted((ROOT/'compiler/core').glob('*.astra')), *sorted((ROOT/'compiler/cfg').glob('*.astra')), ROOT/'tests/selfhost-coreir/mutations.astra', ROOT/'tests/selfhost-cfg/mutations.astra']


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', action='append')
	p.add_argument('--check', action='store_true')
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	a.build.mkdir(parents=True, exist_ok=True)
	attempt = a.runtime/('build-'+str(time.time_ns()))
	attempt.mkdir(parents=True)
	def capture(argv, name, details=None):
		if argv is None:
			(attempt/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n')
			return b''
		if a.check and name.startswith('ownflow-'):
			argv = [*argv[:2], argv[2], '--check', *argv[4:argv.index('--link-object')]]
		start = time.monotonic()
		r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(attempt/(name+'.stdout')).write_bytes(r.stdout); (attempt/(name+'.stderr')).write_bytes(r.stderr)
		(attempt/(name+'.json')).write_text(json.dumps(dict(argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()), indent=2)+'\n')
		print(name, r.returncode, flush=True)
		assert r.returncode == 0, r.stderr.decode(errors='replace')[-6000:]
		if a.check and name.startswith('ownflow-'): raise SystemExit(0)
		return r.stdout
	products = core.base.build(a.compiler.resolve(), a.build.resolve(), capture, a.mode or ('O0', 'O2'), consumer=ROOT/'tests/selfhost-cfg/query.astra', with_flow=True, extra_sources=sources(), product_prefix='astra-cfg-')
	(attempt/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
