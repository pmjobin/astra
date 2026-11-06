#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reuse established independent regression gates in isolated R1 output paths."""
import argparse
from pathlib import Path
import sys
import types
from state import ROOT, load_module, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	runtime = ROOT.parent/'codex/work/astra/runtime/effects25-r1'
	build = ROOT.parent/'codex/work/astra/build/effects25-r1'
	for name in ('inherited', 'continuity', 'memory'):
		module = load_module('r1_'+name, ROOT/('tests/selfhost-effects/'+name+'.py'))
		module.RUNTIME = runtime; module.BUILD = build
		sys.argv = [name, '--mode', a.mode]
		if name != 'memory': sys.argv += ['--component', str(a.component), '--version', 'v1']
		module.main()
	for name in ('negative', 'effect'):
		module = load_module('r1_inherited_'+name, ROOT/('tests/selfhost-callplace/'+name+'.py'))
		module.RUNTIME = runtime; module.BUILD = build
		module.subprocess = types.SimpleNamespace(**vars(module.subprocess)); module.subprocess.run = bounded_run
		sys.argv = [name, '--component', str(a.component), '--version', 'inherited-v1-'+a.mode]
		if name == 'negative': sys.argv += ['--mode', a.mode]
		module.main()


if __name__ == '__main__':
	main()
