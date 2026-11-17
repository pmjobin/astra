#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Small, fail-closed primitives shared by distribution recipes."""
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def require(condition, message):
	if not condition:
		raise ValueError(message)


def sha(path):
	with Path(path).open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def write(path, data):
	path = Path(path)
	path.parent.mkdir(parents=True, exist_ok=True)
	temporary = path.with_name(path.name+'.partial')
	temporary.write_text(json.dumps(data, indent=2, sort_keys=True)+'\n')
	temporary.replace(path)


def identify(path):
	path = Path(path)
	return dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path))


def verify(path, pin):
	path = Path(path)
	require(path.is_file() and not path.is_symlink(), 'missing or symlink input: '+str(path))
	require(path.stat().st_size == pin['bytes'] and sha(path) == pin['sha256'], 'input identity mismatch: '+str(path))
	return path


def external(path, fresh=True):
	path = Path(path).absolute()
	require(not any(p.is_symlink() for p in (path, *path.parents)), 'output traverses symlink')
	require(not path.is_relative_to(ROOT), 'build/runtime output must be outside source')
	path.mkdir(parents=True, exist_ok=not fresh)
	return path


def clean_environment():
	env = dict(os.environ, LC_ALL='C.UTF-8', CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	for key in ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'LIBRARY_PATH', 'CPATH', 'C_INCLUDE_PATH', 'CFLAGS', 'CXXFLAGS', 'LDFLAGS', 'VALGRIND_OPTS'):
		env.pop(key, None)
	return env


def run(argv, directory, env=None, expected=0, timeout=7200, cwd=None):
	"""Retain separate streams, resource usage and failed/interrupted attempts."""
	directory = Path(directory)
	directory.mkdir(parents=True, exist_ok=False)
	argv = list(map(str, argv))
	measured = ['/usr/bin/time', '-v', '-o', str(directory/'time.txt'), *argv] if Path('/usr/bin/time').is_file() else argv
	start = time.monotonic()
	record = dict(argv=argv, cwd=str(cwd or Path.cwd()), expected_exit=expected, status='RUNNING')
	write(directory/'command.json', record)
	with (directory/'stdout').open('wb') as out, (directory/'stderr').open('wb') as err:
		process = subprocess.Popen(measured, stdout=out, stderr=err, env=env, cwd=cwd, start_new_session=True)
		try:
			code = process.wait(timeout=timeout)
		except BaseException:
			os.killpg(process.pid, signal.SIGTERM)
			try:
				process.wait(timeout=5)
			except subprocess.TimeoutExpired:
				os.killpg(process.pid, signal.SIGKILL)
				process.wait()
			record.update(status='INTERRUPTED', exit=process.returncode, seconds=time.monotonic()-start)
			write(directory/'command.json', record)
			raise
	record.update(exit=code, seconds=time.monotonic()-start, status='EXPECTED_OUTCOME' if code == expected else 'FAILED', streams={p.name:identify(p) for p in directory.iterdir() if p.name in ('stdout', 'stderr', 'time.txt')})
	write(directory/'command.json', record)
	require(code == expected, 'command failed: '+str(directory))
	return (directory/'stdout').read_bytes(), (directory/'stderr').read_bytes()
