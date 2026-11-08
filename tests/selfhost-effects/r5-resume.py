#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Continue the published R5 in separate build/runtime leaves."""
import os
from pathlib import Path
import sys
import state

ROOT = state.ROOT
RUNTIME = ROOT.parent/'codex/work/astra/runtime/effects25-r5-resume'
BUILD = ROOT.parent/'codex/work/astra/build/effects25-r5-resume'
PRIOR = RUNTIME.parent/'effects25-r5'


def main():
	assert Path(os.environ['PM_CODEX_BUILD_DIR']).resolve() == BUILD.parent
	assert Path(os.environ['PM_CODEX_RUNTIME_DIR']).resolve() == RUNTIME.parent
	assert (RUNTIME/'initial.json').is_file()
	previous = state.load_module('r5_continuation_route', ROOT/'tests/selfhost-effects/r5.py')
	previous.RUNTIME = RUNTIME
	previous.BUILD = BUILD
	inherited = previous.route()
	def load(name, path):
		module = inherited(name, path)
		if Path(path) == ROOT/'tests/selfhost-effects/full-build.py':
			module.PRIOR = PRIOR/'r4-history/runtime/full-inputs-final16'
		if Path(path) == ROOT/'tests/selfhost-genref/build.py':
			original_build = module.original
			def build(*args, **kwargs):
				kwargs['link_inputs'] = list(dict.fromkeys([*kwargs.get('link_inputs', ()), Path(__file__)]))
				kwargs['extra_sources'] = list(dict.fromkeys([*kwargs.get('extra_sources', ()), ROOT/'tests/selfhost-effects/recover-shared-stage-query.astra', ROOT/'tests/selfhost-effects/recover-shared-mutations.astra', ROOT/'tests/selfhost-effects/recover-frontier-mutations.astra', ROOT/'tests/selfhost-effects/recover-frontier-physical.astra']))
				return original_build(*args, **kwargs)
			module.original = build
		return module
	state.load_module = load
	original_run = state.bounded_run
	def run(argv, **kwargs):
		entries = {str(ROOT/('tests/selfhost-effects/'+name+'.py')) for name in ('r3', 'r4', 'r5')}
		return original_run([Path(__file__) if str(arg) in entries else arg for arg in argv], **kwargs)
	state.bounded_run = run
	recipe = sys.argv.pop(1)
	assert recipe.startswith('recover-') and '/' not in recipe and '.' not in recipe
	module = load('r5_continuation_'+recipe, ROOT/('tests/selfhost-effects/'+recipe+'.py'))
	if hasattr(module, 'main'):
		module.main()
	else:
		runner = load('r5_continuation_corpus', ROOT/'tests/selfhost-effects/recover-qualify.py')
		runner.expanded_corpus = module.corpus
		sys.argv += ['--expanded']
		runner.main()


if __name__ == '__main__':
	main()
