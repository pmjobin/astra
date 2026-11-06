#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh independent C0/design oracles, explicitly separate from Astra effects."""
import argparse
from pathlib import Path
import sys
from state import ROOT, load_module


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path); p.add_argument('--mode', choices=('O0', 'O2')); a = p.parse_args()
	runtime = ROOT.parent/'codex/work/astra/runtime/effects25-r1'
	build = ROOT.parent/'codex/work/astra/build/effects25-r1'
	if a.component:
		assert a.mode
		module = load_module('r1_candidates', ROOT/'tests/selfhost-effects/candidates.py')
		module.RUNTIME = runtime; module.BUILD = build
		sys.argv = ['candidates', '--version', 'v1-'+a.mode, '--mode', a.mode, '--component', str(a.component)]
		module.main()
	else:
		for name in ('c0', 'layout'):
			module = load_module('r1_'+name, ROOT/('tests/selfhost-effects/'+name+'.py'))
			module.RUNTIME = runtime; module.BUILD = build
			sys.argv = [name, '--version', 'v2'] if name == 'c0' else [name]
			module.main()


if __name__ == '__main__':
	main()
