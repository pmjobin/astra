# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Portable proof primitives, with no dependency on untracked local runners."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	with Path(path).open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def write(path, value):
	path = Path(path)
	temporary = path.with_name(path.name+'.tmp-'+str(os.getpid()))
	temporary.write_text(json.dumps(value, indent=2)+'\n')
	temporary.replace(path)


def output_path(path, parent):
	path = Path(path)
	assert path.is_absolute() and path.resolve().is_relative_to(Path(parent).resolve()), path
	assert not any(p.is_symlink() for p in (path, *path.parents)), path
	return path


def tool_identity(paths):
	result = {}
	for path in paths:
		path = Path(path).resolve()
		result[str(path)] = sha(path)
		loaded = subprocess.run(['ldd', str(path)], capture_output=True, text=True)
		assert 'not found' not in loaded.stdout, (path, loaded.stdout)
		for word in loaded.stdout.split():
			if word.startswith('/') and Path(word).is_file():
				dependency = Path(word).resolve()
				result[str(dependency)] = sha(dependency)
	return result


def execute(argv, leaf, expected=0, timeout=300, env=None):
	leaf = Path(leaf)
	leaf.mkdir(parents=True, exist_ok=False)
	start = time.monotonic()
	timed_out = False
	with (leaf/'stdout').open('wb') as out, (leaf/'stderr').open('wb') as err:
		process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/'time.txt'), '--', *map(str, argv)], cwd=ROOT, stdout=out, stderr=err, env=env, start_new_session=True)
		try:
			code = process.wait(timeout=timeout)
		except subprocess.TimeoutExpired:
			timed_out = True
			os.killpg(process.pid, signal.SIGKILL)
			code = process.wait()
	result = dict(status='EXPECTED_OUTCOME' if code == expected and not timed_out else 'UNEXPECTED_OUTCOME', exit=code, expected_exit=expected, timed_out=timed_out, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/'stdout'), stderr_sha256=sha(leaf/'stderr'), time_sha256=sha(leaf/'time.txt'), fresh_execution=True)
	write(leaf/'result.json', result)
	return result
