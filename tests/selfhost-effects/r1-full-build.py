#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""One full R1 qualification build/profile, preserving prior compiler products."""
import argparse
from pathlib import Path
import sys
from state import ROOT, C0, load_module, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	build = ROOT.parent/'codex/work/astra/build/effects25-r1'
	runtime = ROOT.parent/'codex/work/astra/runtime/effects25-r1'
	full = load_module('r1_full_inputs', ROOT/'tests/selfhost-effects/full-build.py')
	full.RUNTIME = runtime; full.BUILD = build; full.INPUTS = runtime/'compiler-inputs-v1'
	full.prepare()
	typecore = (ROOT/'tests/selfhost-effects/r1-typecore.astra').read_text()
	assert typecore.count('int main(string[] args)') == 1
	typecore = typecore.replace('int main(string[] args)', 'int r1_typecore_cli(string[] args)').replace('args[1] == "--mutations"', 'args[1] == "--r1-type-mutations"')
	view = full.INPUTS/'r1-typecore.astra'
	if view.exists(): assert view.read_text() == typecore
	else: view.write_text(typecore)
	genref = load_module('r1_genref_build', ROOT/'tests/selfhost-genref/build.py'); genref.RUNTIME = full.INPUTS
	original = genref.original
	def extend(*args, **kwargs):
		kwargs['consumer'] = ROOT/'tests/selfhost-effects/r1-query.astra'
		kwargs['extra_sources'] = [*kwargs['extra_sources'], full.INPUTS/'genref-query.astra', full.INPUTS/'flow-diagnostic.astra', full.INPUTS/'effects-observe.astra', view, ROOT/'tests/selfhost-effects/source.astra', ROOT/'tests/selfhost-effects/r1-owner.astra']
		kwargs['link_inputs'] = [*kwargs['link_inputs'], Path(__file__), ROOT/'tests/selfhost-effects/observe.astra', ROOT/'tests/selfhost-effects/r1-typecore.astra']
		return original(*args, **kwargs)
	genref.original = extend; genref.base.core.base.build = genref.build
	# The established recipe's command capture retains time/CPU/RSS. Replace
	# only subprocess.run so its existing deadlines terminate the owned group.
	genref.base.subprocess = __import__('types').SimpleNamespace(**vars(genref.base.subprocess))
	def run(argv, **kwargs):
		kwargs.setdefault('timeout', 3600)
		return bounded_run(argv, **kwargs)
	genref.base.subprocess.run = run
	sys.argv = [sys.argv[0], '--compiler', str(C0), '--build', str(build/('compiler-v1-'+a.mode)), '--runtime', str(runtime/('compiler-build-v1-'+a.mode)), '--mode', a.mode]
	genref.base.main()


if __name__ == '__main__':
	main()
