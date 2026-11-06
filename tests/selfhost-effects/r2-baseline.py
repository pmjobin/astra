#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh R2 predecessor native/cohort replay in isolated output directories."""
import argparse
from pathlib import Path
import sys
from state import ROOT, load_module


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--cohorts-only', action='store_true'); a = p.parse_args()
	state = load_module('r2_baseline_state', ROOT/'tests/selfhost-effects/r2-state.py')
	component = ROOT.parent/'codex/work/astra/build/effects25-r1'/('compiler-v1-'+a.mode)/('astra-llvm-'+a.mode)
	for name in (('r1-cohorts',) if a.cohorts_only else ('inherited', 'continuity', 'memory', 'r1-cohorts')):
		module = load_module('r2_baseline_'+name, ROOT/('tests/selfhost-effects/'+name+'.py'))
		module.RUNTIME = state.RUNTIME; module.BUILD = state.BUILD
		if name == 'r1-cohorts':
			module.RUNTIME = state.RUNTIME/'cohort-replay'; module.RUNTIME.mkdir(exist_ok=True)
		sys.argv = [name, '--mode', a.mode]
		if name != 'memory': sys.argv += ['--component', str(component)]
		if name in ('inherited', 'continuity'): sys.argv += ['--version', 'baseline']
		if name == 'memory':
			# The unchanged memory runner reads its local inherited-v1 result.
			module.RUNTIME = state.RUNTIME
			original_read = module.read
			def read(path):
				return original_read(Path(str(path).replace('/inherited-v1-', '/inherited-baseline-')))
			module.read = read
		module.main()
		if name == 'r1-cohorts':
			sys.argv += ['--diagnose-first']; module.main()


if __name__ == '__main__':
	main()
