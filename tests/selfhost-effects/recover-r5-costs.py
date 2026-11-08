#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Keep cold/reuse costs and every GNU-time measurement without double sums."""
import argparse
import json
from pathlib import Path
import sys
from state import ROOT, load_module, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--output', type=Path, required=True); a = p.parse_args(); paths = load_module('r5_cost_paths', ROOT/'tests/selfhost-effects/recover-build.py'); original = load_module('r5_measured_build_costs', ROOT/'tests/selfhost-effects/recover-costs.py')
	sys.argv = [sys.argv[0], '--output', str(a.output)]; original.main(); result = read(a.output); measured = []
	for path in sorted(paths.RUNTIME.rglob('*')):
		if not path.is_file() or path.suffix not in ('.time', '.stderr') and path.name not in ('time',): continue
		first = path.relative_to(paths.RUNTIME).parts[0]
		if first in ('r4-history', 'r4-report-evidence') or first.startswith(('handoff-', 'published-verification-')): continue
		if path.suffix == '.stderr' and not path.parent.name.startswith('build-') and not path.name.startswith('ownflow-'): continue
		values = original.time_values(path)
		if values: measured.append(dict(path=str(path), sha256=sha(path), **values))
	result.update(all_GNU_time_measurements=measured, measurement_accounting='Cold compiler builds/checks and exact reuse have separate entries. Individual test/provider/recipe GNU-time files retain actual wall/user/system/RSS. Parent recipes include child work and concurrent intervals overlap: do not sum parent and child CPU/wall/RSS. Build interval union and sum are explicitly distinct. Pre-compiler preparation failures without GNU time have no invented CPU/RSS values; their tool errors and empty build leaves remain separate from compilation.', uninstrumented_preparation_failures=['full-final1-O0/O2: stopped before compiler invocation because prior cleanup removed genref24/inherited-query.astra; actual later final2 build uses authenticated generated input witnesses', 'initial evidence decode API misuse returned a tuple; corrected without source/report mutation', 'first authentication attempt observed task-authored scope changes; those task-owned scope additions were removed, exact source authentication completed, then additions reapplied'])
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print(len(measured), 'actual GNU-time records retained; no nested CPU total inferred', flush=True)


if __name__ == '__main__':
	main()
