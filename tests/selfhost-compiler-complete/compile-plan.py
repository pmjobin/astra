#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compile an authenticated native-build snapshot with an explicit time budget."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, git, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--identity', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--timeout-seconds', type=int, required=True)
	a = p.parse_args()
	assert a.version.isalnum() and a.timeout_seconds > 0
	assert a.identity.resolve().is_relative_to((WORK/'runtime').resolve())
	assert a.runtime_root.is_absolute() and a.runtime_root.resolve().is_relative_to((WORK/'runtime').resolve())
	assert a.identity.name in ('ownflow-O0-input-identity.json', 'ownflow-O2-input-identity.json')
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	plan = json.loads(a.identity.read_text())
	identity = dict(plan)
	identity['sources'] = dict(plan['sources'])
	identity['sources'][str(Path(__file__).resolve())] = sha(__file__)
	argv = identity['argv']
	assert sha(argv[0]) == C0_SHA256 and argv[1] in ('-O0', '-O2') and argv[-2] == '-o'
	target = Path(argv[-1])
	assert target.is_absolute() and target.resolve().is_relative_to((WORK/'build').resolve())
	assert not target.exists() and not target.with_suffix('.identity.json').exists()
	snapshot = json.loads((a.identity.parent/'snapshot.json').read_text())
	scope = json.loads((a.identity.parent/'scope.json').read_text())
	assert scope['stage'] == 'native'
	compiler = git('ls-tree', '-r', '--name-only', snapshot['revision'], 'compiler').decode().splitlines()
	assert {str(Path(path).relative_to(a.identity.parent/'source-inputs')) for path in scope['compiler_sources']} == {path for path in compiler if path.endswith('.astra')}
	assert all(path in argv for path in scope['compiler_sources'])
	assert all(sha(path) == digest for path, digest in scope['compiler_sources'].items())
	assert all(Path(row['input_path']).stat().st_mode & 0o222 == 0 and sha(row['input_path']) == row['sha256'] for row in snapshot['sources'])
	assert all(git('show', snapshot['revision']+':'+str(Path(row['original_path']).relative_to(ROOT))) == Path(row['input_path']).read_bytes() for row in snapshot['sources'])
	assert all(sha(path) == digest for group in ('sources', 'tools') for path, digest in identity[group].items())
	assert all(os.environ.get(key) == value for key, value in identity['environment'].items())
	assert identity['CCACHE_DISABLE'] == '1'
	env = dict(os.environ, CCACHE_DISABLE='1')
	leaf = a.runtime_root/('compile-plan-'+a.version)
	leaf.mkdir()
	write(leaf/'input-identity.json', identity)
	write(leaf/'plan.json', dict(original_plan=str(a.identity), original_plan_sha256=sha(a.identity), snapshot_sha256=sha(a.identity.parent/'snapshot.json'), scope_sha256=sha(a.identity.parent/'scope.json'), revision=snapshot['revision'], timeout_seconds=a.timeout_seconds))
	started = time.monotonic()
	timed_out = False
	with (leaf/'compile.stdout').open('wb') as stdout, (leaf/'compile.stderr').open('wb') as stderr:
		process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/'compile.time'), *argv], cwd=target.parent, stdout=stdout, stderr=stderr, env=env, start_new_session=True)
		write(leaf/'running.json', dict(pid=process.pid, monotonic_start=started, argv=argv))
		try:
			process.wait(timeout=a.timeout_seconds)
		except subprocess.TimeoutExpired:
			timed_out = True
			os.killpg(process.pid, signal.SIGKILL)
			process.wait()
	result = dict(exit=process.returncode, timed_out=timed_out, seconds=time.monotonic()-started, stdout_sha256=sha(leaf/'compile.stdout'), stderr_sha256=sha(leaf/'compile.stderr'), time_sha256=sha(leaf/'compile.time'), target_native_credit=0)
	if process.returncode == 0 and not timed_out:
		assert all(sha(path) == digest for group in ('sources', 'tools') for path, digest in identity[group].items())
		cache = target.with_suffix('.identity.json')
		write(cache, dict(identity=identity, sha256=sha(target)))
		result['product'] = dict(path=str(target), sha256=sha(target), identity_sha256=sha(cache))
	write(leaf/'result.json', result)
	print(json.dumps(result))
	raise SystemExit(process.returncode if process.returncode >= 0 else 1)


if __name__ == '__main__':
	main()
