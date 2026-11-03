#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-exact Core component builds using the existing out-of-source recipe."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('typecore_build', ROOT / 'tests/selfhost-typecore/build.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'build', 'runtime'):
		p.add_argument('--' + name, type=Path, required=True)
	p.add_argument('--mode', action='append')
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	attempt = a.runtime / ('build-' + str(time.time_ns()))
	attempt.mkdir(parents=True)
	def capture(argv, name, details=None):
		if argv is None:
			(attempt / (name + '.json')).write_text(json.dumps(details, indent=2) + '\n')
			return b''
		t = time.monotonic()
		r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(attempt / (name + '.stdout')).write_bytes(r.stdout)
		(attempt / (name + '.stderr')).write_bytes(r.stderr)
		(attempt / (name + '.json')).write_text(json.dumps(dict(argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-t), indent=2)+'\n')
		print(name, r.returncode, flush=True)
		assert r.returncode == 0, r.stderr.decode(errors='replace')[-5000:]
		return r.stdout
	products = base.build(a.compiler.resolve(), a.build.resolve(), capture, a.mode or ('O0', 'O2'), consumer=ROOT/'tests/selfhost-coreir/query.astra', with_flow=True, extra_sources=[*sorted((ROOT/'compiler/core').glob('*.astra')), ROOT/'tests/selfhost-coreir/mutations.astra'], product_prefix='astra-core-')
	(attempt/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
