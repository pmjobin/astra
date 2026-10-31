#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Read-only source/user/tool inventory; store receipts outside the source tree."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

SOURCE = Path(__file__).resolve().parents[2]


def command(*args):
	p = subprocess.run(args, cwd=SOURCE, text=True, capture_output=True)
	return {'command': list(args), 'returncode': p.returncode,
		'stdout': p.stdout, 'stderr': p.stderr}


def identity(path):
	p = Path(path)
	s = p.lstat()
	return {'sha256': hashlib.sha256(p.read_bytes()).hexdigest(),
		'bytes': s.st_size, 'mode': s.st_mode, 'mtime_ns': s.st_mtime_ns,
		'inode': s.st_ino, 'device': s.st_dev}


def main():
	output = Path(sys.argv[1]).resolve()
	assert not output.is_relative_to(SOURCE)
	output.mkdir(parents=True, exist_ok=True)
	untracked = subprocess.check_output(
		['git', 'ls-files', '--others', '--exclude-standard', '-z'], cwd=SOURCE).decode().split('\0')
	# This test's own new authored files are not preexisting user material.
	user = {p: identity(SOURCE / p) for p in untracked if p and
		not p.startswith(('tests/interop-async-5/', 'examples/interop-async-5/'))}
	record = {'time_ns': time.time_ns(), 'source': str(SOURCE), 'user_files': user,
		'environment': {k: os.environ.get(k) for k in ('CC', 'CXX', 'CCACHE_DISABLE', 'PM_CODEX_BUILD_DIR', 'PKG_CONFIG_PATH')},
		'git': [command('git', *args) for args in [
		('rev-parse', 'HEAD', 'HEAD^{tree}'), ('status', '--short'),
		('worktree', 'list', '--porcelain'), ('diff', '--cached', '--stat'),
		('config', '--show-origin', '--get', 'core.hooksPath'),
		('rev-parse', 'archive/codex-next-20261013'),
		('ls-files', '--others', '--ignored', '--exclude-standard')]],
		'tools': {}, 'kernel': command('uname', '-a')}
	for name in ('valac', 'llvm-config', 'clang-22', 'gcc', 'meson', 'ninja', 'valgrind'):
		path = shutil.which(name)
		record['tools'][name] = {'path': path, 'realpath': str(Path(path).resolve()) if path else None,
			'version': command(name, '--version') if path else None,
			'binary': identity(Path(path).resolve()) if path else None}
	prefix = Path.home() / '.local/opt/liburing-2.15'
	record['liburing'] = {str(p): identity(p) for p in [prefix/'include/liburing.h',
		prefix/'include/liburing/io_uring.h', prefix/'include/liburing/io_uring_version.h',
		prefix/'lib/liburing.a', prefix/'lib/liburing.so.2.15', prefix/'lib/pkgconfig/liburing.pc'] if p.is_file()}
	record['io_uring_disabled'] = Path('/proc/sys/kernel/io_uring_disabled').read_text()
	record['disk'] = command('df', '-h', str(output))
	(output/'initial-state.json').write_text(json.dumps(record, indent=2)+'\n')
	print(f'Inventoried {len(user)} preexisting user files; receipt: {output}/initial-state.json')


if __name__ == '__main__':
	main()
