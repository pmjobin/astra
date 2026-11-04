#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the independent storage consumer with exact source/tool identities."""
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
	p.add_argument('--source-root', type=Path, default=ROOT, help='Explicit retained source snapshot; defaults to the actual repository')
	p.add_argument('--mode', action='append', choices=('O0', 'O2'))
	p.add_argument('--ir', action='store_true', help='Build the LLVM-free Core/CFG/SSA consumer')
	p.add_argument('--check', action='store_true', help='Check the actual consumer sources without generating a binary')
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.build, a.runtime))
	a.build.mkdir(parents=True, exist_ok=True); a.runtime.mkdir(parents=True, exist_ok=False)
	spec = importlib.util.spec_from_file_location('class_storage_base', ROOT/'tests/selfhost-typecore/build.py')
	base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
	base.ROOT = a.source_root.resolve()
	commands = []
	def capture(argv, name, details=None):
		if argv is None:
			(a.runtime/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n'); return b''
		start = time.monotonic()
		if a.check and name.startswith('ownflow-'):
			argv = [*argv[:3], '--check', *argv[4:argv.index('--link-object')]]
		r = subprocess.run(list(map(str, argv)), cwd=a.build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(name, r.returncode, flush=True)
		assert r.returncode == 0, r.stderr.decode(errors='replace')[-3000:]
		if a.check and name.startswith('ownflow-'):
			raise SystemExit(0)
		return r.stdout
	extra = []
	consumer = 'query.astra'
	if a.ir:
		consumer = 'ir-query.astra'
		extra = [path for folder in ('core', 'cfg', 'ssa') for path in sorted((base.ROOT/'compiler'/folder).glob('*.astra'))]
	products = base.build(a.compiler.resolve(), a.build.resolve(), capture, a.mode or ('O0',), with_flow=True, consumer=base.ROOT/'tests/selfhost-classstorage'/consumer, extra_sources=extra, product_prefix='astra-class-ir-' if a.ir else 'astra-class-storage-', link_inputs=[Path(__file__), ROOT/'tests/selfhost-typecore/build.py'])
	(a.runtime/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
