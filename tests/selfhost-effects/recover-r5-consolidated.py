#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""R5 consolidation replaces cleaned-path dependencies with explicit recipes."""
import argparse
import json
import os
from pathlib import Path
import sys
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r5_final_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('consolidated-'+a.version+'-'+a.mode); leaf.mkdir(); identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	jobs = [('recover-r5-inherited', a.version, []), ('recover-r5-cohorts', a.version, []), ('recover-qualify', a.version+'scalar', ['--expanded']), ('recover-record-qualify', a.version+'record', []), ('recover-owned-qualify', a.version+'owned', []), ('recover-error-owned-qualify', a.version+'errors', []), ('recover-loop-qualify', a.version+'loops', []), ('recover-r3-qualify', a.version+'literal', []), ('recover-r3-domain-qualify', a.version+'domain', []), ('recover-adversarial', a.version, []), ('recover-owner-adversarial', a.version, []), ('recover-loop-adversarial', a.version, []), ('recover-r3-adversarial', a.version, []), ('recover-r3-domain-adversarial', a.version, []), ('recover-class-policy', a.version, []), ('recover-r4-policy', a.version, []), ('recover-null-guard', a.version, []), ('recover-r3-receiver-guard', a.version, []), ('recover-r3-float-probe', a.version, []), ('recover-success-probe', a.version, []), ('recover-abi-limit', a.version+a.mode, []), ('recover-original', a.version, ['--provider-build', str(a.component.parent)]), ('recover-r3-original-view', a.version, ['--ledger-component', str(a.component)]), ('recover-frontier', a.version, []), ('recover-r3-fields', a.version+'fields', []), ('recover-r3-source-oracles', a.version, []), ('recover-r3-observe', a.version, ['--native-version', a.version+'literal']), ('recover-r4-qualify', a.version+'fields', []), ('recover-r4-adversarial', a.version, []), ('recover-r4-message', a.version, []), ('recover-r4-lifetime', a.version, []), ('recover-r4-guard', a.version, []), ('recover-r4-loans', a.version, []), ('recover-r4-generic-proof', a.version, []), ('recover-r4-original-view', a.version, ['--ledger-component', str(a.component)]), ('recover-r4-source-policy', a.version, ['--original-version', a.version, '--view-version', a.version, '--minimal-view-version', a.version]), ('recover-r4-layout', a.version, ['--provider-build', str(a.component.parent)]), ('recover-r4-extra-policy', a.version, []), ('recover-r5-prefix', a.version+'prefix', []), ('recover-r5-prefix-negative', a.version, []), ('recover-r5-prefix-literals', a.version, [])]
	commands = []; environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('LD_PRELOAD', None); environment.pop('VALGRIND_OPTS', None)
	for name, version, extra in jobs:
		argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/r5.py', name, '--version', version]
		if name != 'recover-abi-limit': argv += ['--mode', a.mode]
		if name not in ('recover-r3-observe', 'recover-r3-source-oracles', 'recover-r4-layout', 'recover-r4-extra-policy'): argv += ['--component', a.component]
		argv += extra; start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *map(str, argv)], cwd=ROOT, env=environment, capture_output=True, timeout=2400); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, version=version, argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); print(a.mode, name, r.returncode, flush=True)
	failed = [row['name'] for row in commands if row['exit'] != 0]
	(leaf/'result.json').write_text(json.dumps(dict(status='R5_CONSOLIDATED_RECIPES_COMPLETED' if not failed else 'R5_CONSOLIDATED_RECIPES_PARTIAL', profile=a.mode, version=a.version, component=str(a.component), component_sha256=sha(a.component), failed_jobs=failed, jobs=len(jobs), limitation='Completion is a recipe result, not milestone PASS. Historical-path failures remain preserved in baseline receipts. All original-source and effects gates are audited separately.'), indent=2)+'\n')
	if failed: raise SystemExit(1)


if __name__ == '__main__':
	main()
