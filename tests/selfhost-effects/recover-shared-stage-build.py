#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused current Flow/Core/CFG/SSA consumer, without LLVM code generation."""
import argparse
import json
import os
from pathlib import Path
import runpy
import time
from state import ROOT, C0, load_module, bounded_run, sha


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--check', action='store_true')
	a = p.parse_args()
	assert a.version.isalnum()
	paths = load_module('shared_stage_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	build = paths.BUILD/('shared-stage-'+a.version+'-'+a.mode)
	leaf = paths.RUNTIME/('shared-stage-'+a.version+'-'+a.mode)
	leaf.mkdir()
	build.mkdir()
	commands = []
	def capture(argv, name, details=None):
		if argv is None:
			(leaf/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n')
			if details and 'sources' in details:
				for source, expected in details['sources'].items():
					path = Path(source)
					if path.is_relative_to(ROOT):
						assert sha(path) == expected
						target = leaf/'source-witnesses'/path.relative_to(ROOT)
						target.parent.mkdir(parents=True, exist_ok=True)
						if target.exists():
							assert sha(target) == expected
						else:
							target.write_bytes(path.read_bytes())
			return b''
		argv = list(map(str, argv))
		if a.check and name.startswith('typecore-'):
			argv = [*argv[:3], '--dump-core', *argv[4:argv.index('--link-object')]]
		start = time.monotonic()
		r = bounded_run(argv, cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=3600)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(name, r.returncode, flush=True)
		assert r.returncode == 0, r.stderr.splitlines()[:2]
		if a.check and name.startswith('typecore-'):
			raise SystemExit(0)
		return r.stdout
	extra = [*sorted((ROOT/'compiler/core').glob('recover*.astra')), *sorted((ROOT/'compiler/cfg').glob('recover-*.astra')), *sorted((ROOT/'compiler/ssa').glob('recover*.astra')), ROOT/'tests/selfhost-effects/recover-shared-stage-query.astra', ROOT/'tests/selfhost-effects/recover-shared-mutations.astra', ROOT/'tests/selfhost-effects/recover-frontier-mutations.astra']
	base_path = ROOT/'tests/selfhost-typecore/build.py'
	base = runpy.run_path(str(base_path))
	products = base['build'](C0, build, capture, (a.mode,), consumer=ROOT/'tests/selfhost-effects/recover-shared-stage-main.astra', extra_sources=extra, product_prefix='astra-shared-stage-', link_inputs=[Path(__file__), base_path, ROOT/'tests/selfhost-effects/r5-resume.py'])
	(leaf/'products.json').write_text(json.dumps(products, indent=2)+'\n')
	print('Focused current source/ownership stage consumer built; zero target execution credit', flush=True)


if __name__ == '__main__':
	main()
