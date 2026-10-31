#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Record actual system dependency/package licenses without installing anything."""
from pathlib import Path
import hashlib
import re
import shutil
import subprocess


def sha(path):
	with Path(path).open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def package(path):
	path = str(Path(path).resolve())
	if shutil.which('rpm'):
		command = ['rpm', '-qf', '--qf', '%{NAME}\t%{ARCH}\t%{VERSION}-%{RELEASE}\t%{LICENSE}\n', path]
		p = subprocess.run(command, capture_output=True, text=True, timeout=30)
		assert p.returncode == 0, (command, p.stderr)
		rows = [line.split('\t', 3) for line in p.stdout.splitlines()]
		assert rows and all(len(row) == 4 for row in rows), rows
		return {'authority': 'installed RPM database', 'packages': [dict(zip(('name', 'architecture', 'version', 'license_expression'), row)) for row in rows]}
	if shutil.which('dpkg-query'):
		p = subprocess.run(['dpkg-query', '-S', path], capture_output=True, text=True, timeout=30)
		assert p.returncode == 0, (path, p.stderr)
		name = p.stdout.split(': ', 1)[0]
		version = subprocess.check_output(['dpkg-query', '-W', '-f=${Version}', name], text=True)
		copyright = Path('/usr/share/doc') / name.split(':', 1)[0] / 'copyright'
		assert copyright.is_file(), copyright
		return {'authority': 'installed dpkg database and copyright file', 'name': name,
			'version': version, 'copyright_path': str(copyright), 'copyright_sha256': sha(copyright),
			'copyright_text': copyright.read_text()}
	raise AssertionError('dependency license inventory needs installed RPM or dpkg package metadata')


def inventory(compiler, liburing_prefix=None):
	compiler = Path(compiler)
	p = subprocess.run(['ldd', str(compiler)], capture_output=True, text=True, timeout=30)
	assert p.returncode == 0 and 'not found' not in p.stdout, p.stdout + p.stderr
	libraries = []
	for line in p.stdout.splitlines():
		match = re.search(r'(?:=>\s+)?(/\S+)\s+\(', line)
		if match is None:
			assert 'linux-vdso' in line or not line.strip(), line
			continue
		path = Path(match.group(1)).resolve()
		libraries.append({'soname': line.strip().split()[0], 'resolved_path': str(path),
			'sha256': sha(path), 'package_license': package(path)})
	assert libraries
	tools = []
	for name, arguments in [('valac', ['--version']), ('cc', ['--version']), ('meson', ['--version']),
		('ninja', ['--version']), ('llvm-config', ['--version']), ('python3', ['--version'])]:
		path = shutil.which(name)
		assert path, name
		p = subprocess.run([path, *arguments], capture_output=True, text=True, timeout=30)
		assert p.returncode == 0, p.stderr
		tools.append({'tool': name, 'version_output': p.stdout.strip(), 'executable_sha256': sha(path),
			'package_license': package(path)})
	result = {'format': 'astra-third-party-inventory/1',
		'astra_license': 'Apache-2.0 WITH LLVM-exception',
		'system_libraries_bundled': False,
		'license_scope': 'Exact installed package expressions describe package contents; individual files retain their notices. System shared-library binaries are external requirements.',
		'compiler_system_libraries': libraries, 'stage0_build_tools': tools}
	if liburing_prefix:
		prefix = Path(liburing_prefix)
		pc = prefix / 'lib/pkgconfig/liburing.pc'
		version = re.search(r'^Version:\s*(\S+)', pc.read_text(), re.M)
		assert version
		headers = []
		for path in sorted((prefix / 'include').rglob('*.h')):
			text = path.read_text()
			headers.append({'path': str(path.relative_to(prefix)), 'sha256': sha(path),
				'spdx': re.findall(r'SPDX-License-Identifier:\s*([^*\n]+)', text)})
		archive = prefix / 'lib/liburing.a'
		result['optional_liburing'] = {'version': version.group(1), 'pkg_config_sha256': sha(pc),
			'archive_sha256': sha(archive), 'headers': headers,
			'archive_bundled': False, 'inline_header_license_choice': 'MIT',
			'notice': 'liburing-MIT.txt', 'notice_source': 'https://github.com/axboe/liburing/blob/liburing-2.15/LICENSE'}
	return result
