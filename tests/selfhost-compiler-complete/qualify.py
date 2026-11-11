#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh current-profile regressions; historical failed campaigns stay failed."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from run import ROOT, WORK, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--component', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--build-version', required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--jobs', type=int, choices=range(1, 9), default=1)
	a = p.parse_args()
	assert a.version.isalnum() and a.build_version.isalnum()
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
	assert all(sha(name) == h for group in ('sources', 'tools') for name, h in identity['identity'][group].items())
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('qualification-'+a.version+'-'+a.mode)
	leaf.mkdir()
	native = a.runtime_root/('native-frontiers-'+a.version+'-'+a.mode)/'result.json'
	extra = WORK/('runtime/effects25-r5-resume/native-frontiers-errorextra1-'+a.mode+'/result.json')
	assert extra.is_file()
	jobs = [
		('original-and-owner-native', 'recover-native-frontiers', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('source-stage-mutations', 'recover-stage-frontiers', ['--observer', a.component, '--version', a.version+a.mode, '--fixtures', native]),
		('array-source-negatives', 'recover-array-source-negative', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('owner-source-negatives', 'recover-owner-source-negative', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('dynamic-source-faults', 'recover-dynamic-faults', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('error-order', 'recover-error-order-native', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('error-lifetime', 'recover-error-lifetime', ['--component', a.component, '--mode', a.mode, '--version', a.version, '--fixtures', extra]),
		('frontier-physical', 'recover-frontier-physical-proof', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('error-physical', 'recover-error-physical-proof', ['--component', a.component, '--mode', a.mode, '--version', a.version, '--valid-field-receiver']),
		('exact-identity-reuse', 'recover-r5-warm', ['--component', a.component, '--mode', a.mode, '--version', a.build_version]),
		('retained-41-recipes', 'recover-resume-retained', ['--component', a.component, '--mode', a.mode, '--version', a.version]),
		('strict-raw-drift', 'recover-resume-retained', ['--recipe', 'recover-r5-drift', '--mode', a.mode, '--version', a.version]),
	]
	commands = []
	env = dict(os.environ, CCACHE_DISABLE='1')
	for name in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE'):
		env.pop(name, None)

	def run(job, dependency):
		if dependency is not None:
			dependency.result()
		name, recipe, extra_args = job
		argv = list(map(str, [sys.executable, '-B', Path(__file__).with_name('route.py'), '--build-root', a.build_root, '--runtime-root', a.runtime_root, recipe, *extra_args]))
		started = time.monotonic()
		with (leaf/(name+'.stdout')).open('wb') as out, (leaf/(name+'.stderr')).open('wb') as err:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=ROOT, env=env, stdout=out, stderr=err, start_new_session=True)
			timed_out = False
			try:
				code = process.wait(7200)
			except subprocess.TimeoutExpired:
				timed_out = True
				os.killpg(process.pid, signal.SIGKILL)
				code = process.wait()
		print(a.mode, name, code, flush=True)
		return dict(name=name, argv=argv, exit=code, timed_out=timed_out, start=started, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))

	dependencies = {'source-stage-mutations': 'original-and-owner-native', 'strict-raw-drift': 'retained-41-recipes'}
	with ThreadPoolExecutor(max_workers=a.jobs) as pool:
		futures = {}
		for job in jobs:
			futures[job[0]] = pool.submit(run, job, futures.get(dependencies.get(job[0])))
		completed = {}
		for future in as_completed(futures.values()):
			row = future.result()
			completed[row['name']] = row
			commands = [completed[name] for name, _, _ in jobs if name in completed]
			write(leaf/'commands.json', commands)
			failed = [row['name'] for row in commands if row['exit'] != 0 or row['timed_out']]
			write(leaf/'result.json', dict(status='CONTINUATION_QUALIFICATION_PARTIAL' if failed else 'CONTINUATION_QUALIFICATION_IN_PROGRESS', milestone='ASTRA-SELFHOST-COMPILER-COMPLETE-26', profile=a.mode, component_sha256=sha(a.component), selected_jobs=None, completed_jobs=len(commands), expected_jobs=len(jobs), failed_jobs=failed, workers=a.jobs, dependencies=dependencies, historical_extra_fixture=dict(path=str(extra), sha256=sha(extra)), limitation='Fresh milestone26 campaign with the previously qualified LLVM-valid receiver setter explicitly enabled. This does not relabel either raw failed R5 campaign. No campaign count or passing subset proves full original compiler completeness.'))
	result = json.loads((leaf/'result.json').read_text())
	result['status'] = 'CONTINUATION_QUALIFICATION_PARTIAL' if result['failed_jobs'] else 'CONTINUATION_QUALIFICATION_COMPLETED'
	write(leaf/'result.json', result)
	if result['failed_jobs']:
		raise SystemExit(1)


if __name__ == '__main__':
	main()
