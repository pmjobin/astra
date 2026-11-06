#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh unchanged C0 and GCC/Clang layout oracles, never Astra ELF evidence."""
import sys
from state import ROOT, load_module


def main():
	state = load_module('r2_oracle_state', ROOT/'tests/selfhost-effects/r2-state.py')
	runtime = state.RUNTIME/'final'; runtime.mkdir(exist_ok=True)
	build = state.BUILD/'qualification'; build.mkdir(exist_ok=True)
	for name in ('c0', 'layout'):
		module = load_module('r2_oracle_'+name, ROOT/('tests/selfhost-effects/'+name+'.py'))
		module.RUNTIME = runtime; module.BUILD = build
		sys.argv = [name, '--version', 'v2'] if name == 'c0' else [name]
		module.main()


if __name__ == '__main__':
	main()
