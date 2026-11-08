#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run every continuation gate independently; preserve and report all failures."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--component', type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--build-version', required=True)
	p.add_argument('--job', action='append')
	a = p.parse_args()
	assert a.version.isalnum() and a.build_version.isalnum()
	identity = read(a.component.with_suffix('.identity.json'))
	assert a.component.name == 'astra-llvm-'+a.mode and sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
	assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	paths = load_module('resume_qualification_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('qualification-'+a.version+'-'+a.mode)
	leaf.mkdir()
	native_fixture = paths.RUNTIME/('native-frontiers-'+a.version+'-'+a.mode)/'result.json'
	extra_fixture = paths.RUNTIME/('native-frontiers-errorextra1-'+a.mode)/'result.json'
	jobs = [
		('original-and-owner-native', 'recover-native-frontiers', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('source-stage-mutations', 'recover-stage-frontiers', ['--observer', a.component, '--version', a.version+a.mode, '--fixtures', native_fixture]),
		('array-source-negatives', 'recover-array-source-negative', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('owner-source-negatives', 'recover-owner-source-negative', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('dynamic-source-faults', 'recover-dynamic-faults', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('error-order', 'recover-error-order-native', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('error-lifetime', 'recover-error-lifetime', ['--component', a.component, '--mode', a.mode, '--version', a.version, '--fixtures', extra_fixture]),
		('frontier-physical', 'recover-frontier-physical-proof', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('error-physical', 'recover-error-physical-proof', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('exact-identity-reuse', 'recover-r5-warm', ['--component', a.component, '--mode', a.mode, '--version', a.build_version]),
		('retained-41-recipes', 'recover-resume-retained', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('strict-raw-drift', 'recover-resume-retained', ['--recipe', 'recover-r5-drift', '--mode', a.mode, '--version', a.version]),
	]
	if a.job:
		assert set(a.job) <= {name for name, _, _ in jobs}
	env = dict(os.environ, CCACHE_DISABLE='1')
	for key in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE'):
		env.pop(key, None)
	commands = []
	for name, recipe, extra in jobs:
		if a.job and name not in a.job: continue
		argv = list(map(str, [sys.executable, '-B', ROOT/'tests/selfhost-effects/r5-resume.py', recipe, *extra]))
		started = time.monotonic()
		try:
			r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=ROOT, env=env, capture_output=True, timeout=7200)
			exit_code, stdout, stderr = r.returncode, r.stdout, r.stderr
			timed_out = False
		except subprocess.TimeoutExpired as error:
			exit_code, stdout, stderr = None, error.output or b'', error.stderr or b''
			timed_out = True
		(leaf/(name+'.stdout')).write_bytes(stdout)
		(leaf/(name+'.stderr')).write_bytes(stderr)
		commands.append(dict(name=name, argv=argv, exit=exit_code, timed_out=timed_out, start=started, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		failed = [row['name'] for row in commands if row['exit'] != 0 or row['timed_out']]
		(leaf/'result.json').write_text(json.dumps(dict(status='CONTINUATION_QUALIFICATION_PARTIAL' if failed else 'CONTINUATION_QUALIFICATION_IN_PROGRESS', profile=a.mode, component_sha256=sha(a.component), selected_jobs=a.job, completed_jobs=len(commands), expected_jobs=len(jobs) if not a.job else len(set(a.job)), failed_jobs=failed, limitation='Every job has independent actual command/stdout/stderr/time receipts. Failures, signals and deadline stops remain failures; child recipes retain their own command deadlines and receipts. A filtered run or an in-progress incremental result cannot establish milestone completion. Source snapshots are inputs/witnesses; only actual matched-profile target executions receive native credit.'), indent=2)+'\n')
		print(a.mode, name, 'deadline stop' if timed_out else exit_code, flush=True)
	result = read(leaf/'result.json')
	result['status'] = 'CONTINUATION_QUALIFICATION_PARTIAL' if result['failed_jobs'] else 'CONTINUATION_QUALIFICATION_COMPLETED'
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	if result['failed_jobs']: raise SystemExit(1)


if __name__ == '__main__':
	main()
