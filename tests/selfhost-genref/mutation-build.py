#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the separate reference mutation consumer at an explicit profile."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args()
	directory = BUILD/('mutator-'+a.version+'-'+a.mode); directory.mkdir(exist_ok=False)
	leaf = RUNTIME/('mutator-build-'+a.version+'-'+a.mode); leaf.mkdir(exist_ok=False); commands = []
	spec = importlib.util.spec_from_file_location('typecore_build', ROOT/'tests/selfhost-typecore/build.py')
	base = importlib.util.module_from_spec(spec); spec.loader.exec_module(base)
	# Execute the actual previous predicate on the same forged models. Its bytes
	# are pinned by the successful v1 compiler identity and retained snapshot.
	previous = RUNTIME/'data-full-v1-O0/implementation/compiler/semantic/generic-check.astra'
	product = BUILD/'compiler-v1-O0/astra-llvm-O0.identity.json'
	assert sha(previous) == read(product)['identity']['sources'][str(ROOT/'compiler/semantic/generic-check.astra')]
	text = previous.read_text(); first = text.index('int generic_verify_failure('); last = text.index('\nbool generic_verify(', first)
	predicate = text[first:last].replace('int generic_verify_failure(', 'int genref_before_verify_failure(').replace('generic_references_verified(', 'genref_before_references_verified(')
	first = text.index('bool generic_references_verified('); last = text.index('\n// Independent storage-bound checks', first)
	predicate += '\n'+text[first:last].replace('bool generic_references_verified(', 'bool genref_before_references_verified(')
	baseline = RUNTIME/'completion-baseline-v1.astra'; expected = '// Read-only exact v1 predicate, entrypoints renamed for comparison.\n'+predicate
	if baseline.exists(): assert baseline.read_text() == expected
	else: baseline.write_text(expected)
	def capture(argv, name, details=None):
		if argv is None:
			(leaf/(name+'.json')).write_text(json.dumps(details, indent=2)+'\n'); return b''
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=directory, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		print(name, r.returncode, flush=True); assert r.returncode == 0, r.stderr.decode(errors='replace').split('Command being timed')[0][-3000:]; return r.stdout
	products = base.build(C0, directory, capture, (a.mode,), consumer=ROOT/'tests/selfhost-genref/mutation-query.astra', with_flow=True, extra_sources=[ROOT/'tests/selfhost-genref/check.astra', baseline], product_prefix='genref-mutator-', link_inputs=[Path(__file__), previous, product])
	(leaf/'products.json').write_text(json.dumps(products, indent=2)+'\n')


if __name__ == '__main__':
	main()
