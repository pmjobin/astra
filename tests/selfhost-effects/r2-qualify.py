#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""One consolidated current-compiler qualification/profile in isolated R2 paths."""
import argparse
from pathlib import Path
import sys
import types
from state import ROOT, load_module, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	state = load_module('r2_final_state', ROOT/'tests/selfhost-effects/r2-state.py')
	runtime = state.RUNTIME/'final'; runtime.mkdir(exist_ok=True)
	build = state.BUILD/'qualification'; build.mkdir(exist_ok=True)
	component = state.BUILD/('compiler-v1-'+a.mode)/('astra-llvm-'+a.mode)
	for name in ('inherited', 'continuity', 'memory', 'r1-cohorts', 'r1-ledgers'):
		module = load_module('r2_final_'+name, ROOT/('tests/selfhost-effects/'+name+'.py'))
		module.RUNTIME = runtime; module.BUILD = build
		sys.argv = [name, '--mode', a.mode]
		if name != 'memory': sys.argv += ['--component', str(component)]
		if name in ('inherited', 'continuity'): sys.argv += ['--version', 'v1']
		module.main()
		if name == 'r1-cohorts': sys.argv += ['--diagnose-first']; module.main()
	for name in ('negative', 'effect'):
		module = load_module('r2_final_'+name, ROOT/('tests/selfhost-callplace/'+name+'.py'))
		module.RUNTIME = runtime; module.BUILD = build
		module.subprocess = types.SimpleNamespace(**vars(module.subprocess)); module.subprocess.run = bounded_run
		sys.argv = [name, '--component', str(component), '--version', 'v1-'+a.mode]
		if name == 'negative': sys.argv += ['--mode', a.mode]
		module.main()
	module = load_module('r2_final_candidates', ROOT/'tests/selfhost-effects/candidates.py'); module.RUNTIME = runtime; module.BUILD = build
	sys.argv = ['candidates', '--version', 'v1-'+a.mode, '--component', str(component), '--mode', a.mode]; module.main()
	for name in ('r2-frontier', 'r2-abi-qualify'):
		module = load_module('r2_final_'+name, ROOT/('tests/selfhost-effects/'+name+'.py'))
		sys.argv = [name, '--mode', a.mode, '--component', str(component)]; module.main()


if __name__ == '__main__':
	main()
