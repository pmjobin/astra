#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the observer externally through the pinned independent C0."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, load_module


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args()
	directory = BUILD/('observer-'+a.version); directory.mkdir(exist_ok=False)
	leaf = RUNTIME/('observer-build-'+a.version); leaf.mkdir(exist_ok=False); commands = []
	base = load_module('effects_typecore_build', ROOT/'tests/selfhost-typecore/build.py')
	def capture(argv, name, details=None):
		if argv is None:
			if 'sources' in details:
				for path in details['sources']:
					source = Path(path)
					if source.is_relative_to(ROOT):
						target = leaf/'inputs'/source.relative_to(ROOT); target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(source.read_bytes())
			(leaf/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n'); return b''
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=directory, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start)); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(name, r.returncode, flush=True); assert r.returncode == 0, r.stderr.decode(errors='replace')[-3000:]; return r.stdout
	products = base.build(C0, directory, capture, ('O0',), consumer=ROOT/'tests/selfhost-effects/observe.astra', with_flow=True, product_prefix='effects-observer-', link_inputs=[Path(__file__)])
	(leaf/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
