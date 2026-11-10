#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay two missing-fixture jobs separately; keep the failed campaign intact."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from run import ROOT, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--component', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--raw-version', required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	a = p.parse_args()
	assert a.version.isalnum() and a.raw_version.isalnum()
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
	assert all(sha(path) == h for group in ('sources', 'tools') for path, h in identity['identity'][group].items())
	seed = a.runtime_root/'reference-fixture-seed.json'
	for row in json.loads(seed.read_text())['files']:
		assert sha(row['original']) == row['original_sha256'] == sha(row['snapshot'])
		assert Path(row['snapshot']).stat().st_mode & 0o222 == 0
	raw = a.runtime_root/('qualification-'+a.raw_version+'-'+a.mode)
	failed = [row for row in json.loads((raw/'commands.json').read_text()) if row['exit'] != 0]
	assert [row['name'] for row in failed] == ['error-order', 'error-physical']
	assert all('FileNotFoundError:' in (raw/(row['name']+'.stderr')).read_text() for row in failed)
	leaf = a.runtime_root/('fixture-supplements-'+a.version+'-'+a.mode)
	leaf.mkdir()
	(leaf/'raw-campaign-at-start.json').write_bytes((raw/'result.json').read_bytes())
	commands = []
	for name, recipe, extra in (('error-order', 'recover-error-order-native', []), ('error-physical', 'recover-error-physical-proof', ['--valid-field-receiver'])):
		argv = list(map(str, [sys.executable, '-B', Path(__file__).with_name('route.py'), '--build-root', a.build_root, '--runtime-root', a.runtime_root, recipe, '--mode', a.mode, '--component', a.component, '--version', a.version, *extra]))
		start = time.monotonic()
		with (leaf/(name+'.stdout')).open('wb') as out, (leaf/(name+'.stderr')).open('wb') as err:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=ROOT, stdout=out, stderr=err, start_new_session=True)
			timed_out = False
			try:
				code = process.wait(900)
			except subprocess.TimeoutExpired:
				timed_out = True
				os.killpg(process.pid, signal.SIGKILL)
				code = process.wait()
		commands.append(dict(name=name, argv=argv, exit=code, timed_out=timed_out, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		write(leaf/'commands.json', commands)
		print(a.mode, name, code, flush=True)
	failed_new = [row['name'] for row in commands if row['exit'] != 0 or row['timed_out']]
	write(leaf/'result.json', dict(status='FIXTURE_SUPPLEMENTS_PASSED' if not failed_new else 'FIXTURE_SUPPLEMENTS_FAILED', component_sha256=sha(a.component), profile=a.mode, version=a.version, raw_version=a.raw_version, selected_jobs=['error-order', 'error-physical'], completed_jobs=len(commands), failed_jobs=failed_new, raw_failed_commands=failed, input_seed_sha256=sha(seed), raw_campaign_snapshot_sha256=sha(leaf/'raw-campaign-at-start.json'), limitation='Two fresh corrected-input jobs only. The raw milestone26 campaign and its missing-fixture failures remain unchanged and failed. The snapshot can precede completion of the other raw jobs. Independent detailed receipt/ELF/source/memory/LLVM-valid-mutation verification is required; successful wrapper exits alone confer no qualification.'))
	if failed_new:
		raise SystemExit(1)


if __name__ == '__main__':
	main()
