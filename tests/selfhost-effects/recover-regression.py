#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh inherited/native/cohort replay without touching historical outputs."""
import argparse
import json
from pathlib import Path
import sys
from state import ROOT, load_module, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); p.add_argument('--cohorts-only', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('recover_regression_paths', ROOT/'tests/selfhost-effects/recover-build.py'); runtime = paths.RUNTIME/('regression-'+a.version+'-'+a.mode); build = paths.BUILD/runtime.name; runtime.mkdir(); build.mkdir()
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']; assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	names = ('r1-cohorts', 'r1-ledgers') if a.cohorts_only else ('inherited', 'continuity', 'memory', 'r1-cohorts', 'r1-ledgers')
	for name in names:
		module = load_module('recover_regression_'+name, ROOT/('tests/selfhost-effects/'+name+'.py')); module.RUNTIME = runtime; module.BUILD = build
		sys.argv = [name, '--mode', a.mode]
		if name != 'memory': sys.argv += ['--component', str(a.component)]
		if name in ('inherited', 'continuity'): sys.argv += ['--version', 'v1']
		module.main()
		if name == 'r1-cohorts': sys.argv += ['--diagnose-first']; module.main()
	(runtime/'result.json').write_text(json.dumps(dict(status='FRESH_FROZEN_COHORT_REPLAY' if a.cohorts_only else 'FRESH_INHERITED_AND_COHORT_REPLAY', component_sha256=sha(a.component), profile=a.mode, inherited_programs=0 if a.cohorts_only else 202, routines=list(names), limitation='Recoverable-effect qualification is separate. Original source attempts and the independently deferred predicate 26 retain their actual outcomes.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
