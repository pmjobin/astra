#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused Typecore producer build using the actual unchanged source route."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import time
from state import ROOT, C0, load_module, bounded_run, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_type_proof_paths', ROOT/'tests/selfhost-effects/recover-build.py'); build = paths.BUILD/('typeproof-'+a.version+'-'+a.mode); leaf = paths.RUNTIME/('build-typeproof-'+a.version+'-'+a.mode)/str(time.time_ns()); leaf.mkdir(parents=True); commands = []
	def capture(argv, name, details=None):
		if argv is None:
			if details and 'sources' in details:
				key = hashlib.sha256(json.dumps(details, sort_keys=True).encode()).hexdigest(); snapshot = paths.RUNTIME/'compiler-inputs'/key
				for source, expected in details['sources'].items():
					if Path(source).is_relative_to(ROOT):
						assert sha(source) == expected; target = snapshot/Path(source).relative_to(ROOT); target.parent.mkdir(parents=True, exist_ok=True)
						if target.exists(): assert sha(target) == expected
						else: target.write_bytes(Path(source).read_bytes())
				(snapshot/'identity.json').write_text(json.dumps(details, indent=2)+'\n')
			(leaf/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n'); return b''
		if name.startswith('ownflow-'): name = name.replace('ownflow-', 'typecore-', 1)
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(argv, cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=3600); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); print(name, r.returncode, flush=True); assert r.returncode == 0, r.stderr[-4000:]; return r.stdout
		# Load the unchanged builder directly: the inherited route additionally
		# injects LLVM mutation consumers, which belong to the full qualification.
		# This focused source observer has no LLVM emission or mutation credit.
	observer = ROOT/'tests/selfhost-effects/observe.astra'; text = observer.read_bytes(); end = text.index(b'int main(string[] args)'); view = leaf/'effects-observe.astra'; view.write_bytes(text[:end]); (leaf/'observer-view.json').write_text(json.dumps(dict(original=str(observer), original_sha256=sha(observer), end_byte=end, view=str(view), view_sha256=sha(view), attribution='Complete unchanged observation functions; the unrelated entry point alone is omitted. No compiler function or verifier body is substituted.'), indent=2)+'\n')
	base_path = ROOT/'tests/selfhost-typecore/build.py'; base = runpy.run_path(str(base_path)); products = base['build'](C0, build, capture, (a.mode,), consumer=ROOT/'tests/selfhost-effects/recover-r4-type-query.astra', with_flow=True, extra_sources=[ROOT/'tests/selfhost-effects/recover-r4-observe.astra', ROOT/'tests/selfhost-effects/r1-owner.astra', view], product_prefix='astra-typeproof-', link_inputs=[Path(__file__), base_path, observer, ROOT/'tests/selfhost-effects/r4.py']); (leaf/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
