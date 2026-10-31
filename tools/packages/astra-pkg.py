#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Offline, integrity-locked source and native-unit packages for astrac."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile

MANIFEST = 'astra-package.json'
LOCK = 'astra-package.lock'
FORMAT = 'astra-package/1'
NAME = re.compile(r'[a-z][a-z0-9-]{0,63}\Z')
VERSION = re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\Z')
ROLES = ('sources', 'vapi', 'native_modules', 'objects', 'assets')
REQUIRED = {'format', 'name', 'version', 'compiler', 'abi', 'license', 'sources', 'dependencies'}
FIELDS = REQUIRED | set(ROLES) | {'libraries'}


class PackageError(Exception):
	pass


def require(condition, reason):
	if not condition:
		raise PackageError(reason)


def encoded(value):
	return (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + '\n').encode()


def digest(data):
	return hashlib.sha256(data).hexdigest()


def unique_object(pairs):
	result = {}
	for key, value in pairs:
		require(key not in result, f'duplicate JSON key: {key}')
		result[key] = value
	return result


def safe_absolute(path):
	"""Check the written path before normalization can conceal a symlink."""
	require('..' not in Path(path).parts, f'parent traversal is not a package path: {path}')
	path = Path(os.path.abspath(path))
	current = Path(path.anchor)
	for component in path.parts[1:]:
		current /= component
		require(not current.is_symlink(), f'symlink path is not a package input/output: {current}')
	return path


def member(root, name):
	require(isinstance(name, str) and name and '\\' not in name and '\x00' not in name,
		'invalid package member path')
	parts = name.split('/')
	require(not PurePosixPath(name).is_absolute() and all(p not in ('', '.', '..') for p in parts)
		and all(not p.startswith('.') for p in parts), f'unsafe package member path: {name}')
	return safe_absolute(root.joinpath(*parts))


def read_regular(path, limit=16 * 1024 * 1024):
	path = safe_absolute(path)
	s = path.stat()
	require(stat.S_ISREG(s.st_mode) and s.st_size <= limit, f'not a bounded regular file: {path}')
	return path.read_bytes()


def read_json(path):
	value = json.loads(read_regular(path, 1024 * 1024), object_pairs_hook=unique_object)
	require(isinstance(value, dict), f'expected JSON object: {path}')
	return value


class Package:
	def __init__(self, root):
		self.root = safe_absolute(root)
		self.data = read_json(self.root / MANIFEST)
		d = self.data
		require(REQUIRED <= d.keys() <= FIELDS, f'unknown/missing manifest fields: {self.root}')
		require(d['format'] == FORMAT, 'unsupported package manifest version')
		require(isinstance(d['name'], str) and NAME.fullmatch(d['name']), 'invalid package name')
		for field in ('version', 'compiler'):
			require(isinstance(d[field], str) and VERSION.fullmatch(d[field]), f'invalid exact {field} version')
		require(d['abi'] == 'source+native-unit/1', 'unsupported package ABI contract')
		require(isinstance(d['license'], str) and 0 < len(d['license']) <= 200, 'explicit license required')
		require(isinstance(d['dependencies'], dict) and len(d['dependencies']) <= 128, 'invalid dependency map')
		for name, version in d['dependencies'].items():
			require(NAME.fullmatch(name) and isinstance(version, str) and VERSION.fullmatch(version),
				'invalid dependency name or exact version')
		self.files = {MANIFEST: digest(read_regular(self.root / MANIFEST))}
		used = set()
		for role in ROLES:
			values = d.get(role, [])
			require(isinstance(values, list) and len(values) <= 1024, f'invalid file list: {role}')
			for name in values:
				path = member(self.root, name)
				require(name not in used and name not in (MANIFEST, LOCK), f'duplicate/reserved file: {name}')
				used.add(name)
				self.files[name] = digest(read_regular(path))
		require(d['sources'] or d.get('native_modules'), 'package needs source or a native module')
		libraries = d.get('libraries', [])
		require(isinstance(libraries, list) and len(libraries) <= 128 and all(
			isinstance(n, str) and re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', n) for n in libraries),
			'invalid explicit linker library')
		# Native-unit validation remains in astrac. Ensure its sibling object is
		# part of this package's integrity inventory and installation as well.
		for name in d.get('native_modules', []):
			text = read_regular(member(self.root, name)).decode('utf-8')
			section = None
			objects = []
			for line in text.splitlines():
				if line.startswith('['):
					section = line
				elif section == '[object]' and line.startswith('file='):
					objects.append(line[5:])
			require(len(objects) == 1 and '/' not in objects[0] and '\\' not in objects[0],
				'invalid native-unit sibling object')
			obj = str(PurePosixPath(name).parent / objects[0])
			require(obj in self.files and obj in d.get('assets', []),
				'native-unit object must be declared as an integrity-checked asset')


def compiler_identity(path):
	path = Path(shutil.which(str(path)) or path).resolve(strict=True)
	def query(flag):
		p = subprocess.run([str(path), flag], capture_output=True, text=True, timeout=30)
		require(p.returncode == 0, f'compiler {flag} failed: {p.stderr.strip()}')
		return p.stdout.strip()
	version = query('--version')
	match = re.match(r'astrac ([0-9]+\.[0-9]+\.[0-9]+) ', version)
	require(match, 'unrecognized astrac version')
	return path, {'version': match[1], 'sha256': digest(path.read_bytes()), 'target': query('--target-info')}


def resolve(root, paths, prefix, compiler):
	root = Package(root)
	candidates = {}
	for path in paths:
		p = Package(path)
		key = p.data['name']
		require(key != root.data['name'] and key not in candidates, f'duplicate package name: {key}')
		candidates[key] = p
	selected, active, order = {}, set(), []

	def visit(p, depth=0):
		require(depth <= 128 and len(selected) <= 128, 'package graph exceeds finite limit')
		name = p.data['name']
		require(name not in active, f'dependency cycle at {name}')
		if name in selected:
			require(selected[name].root == p.root, f'conflicting package identity: {name}')
			return
		require(p.data['compiler'] == compiler['version'], f'incompatible compiler version: {name}')
		selected[name] = p
		active.add(name)
		for dep, version in sorted(p.data['dependencies'].items()):
			if dep == root.data['name']:
				other = root
			elif dep in candidates:
				other = candidates[dep]
			else:
				other = Package(prefix / 'share/astra/packages' / dep / version)
			require(other.data['name'] == dep and other.data['version'] == version,
				f'incompatible dependency version: {name} needs {dep}@{version}')
			visit(other, depth + 1)
		active.remove(name)
		order.append(p)

	visit(root)
	require(set(candidates) <= selected.keys(), 'unused explicit dependency path')
	lock = {'format': 'astra-package-lock/1', 'root': root.data['name'], 'compiler': compiler,
		'packages': [{'name': n, 'version': p.data['version'], 'files': p.files}
		for n, p in sorted(selected.items())]}
	return root, order, lock


def exclusive_json(path, data):
	with path.open('xb') as f:
		f.write(encoded(data))


def install(order, prefix, lock):
	store = safe_absolute(prefix / 'share/astra/packages')
	store.mkdir(parents=True, exist_ok=True)
	for p in order:
		parent = safe_absolute(store / p.data['name'])
		parent.mkdir(exist_ok=True)
		destination = safe_absolute(parent / p.data['version'])
		if destination.exists():
			require(Package(destination).files == p.files, f'existing installed identity differs: {destination}')
			continue
		stage = Path(tempfile.mkdtemp(prefix='package-', dir=parent))
		try:
			for name, expected in p.files.items():
				data = read_regular(member(p.root, name))
				require(digest(data) == expected, f'package changed during installation: {name}')
				out = stage / name
				out.parent.mkdir(parents=True, exist_ok=True)
				out.write_bytes(data)
				require(digest(out.read_bytes()) == expected, 'installed content differs')
			(stage / 'astra-installed.json').write_bytes(encoded({'format': 'astra-installed-package/1',
				'compiler': lock['compiler'], 'name': p.data['name'], 'files': p.files}))
			# Never replace an existing version, even if another installer races.
			destination.mkdir()
			try:
				for child in stage.iterdir():
					os.rename(child, destination / child.name)
			except BaseException:
				shutil.rmtree(destination)
				raise
		finally:
			shutil.rmtree(stage)
		print(f'installed {p.data["name"]}@{p.data["version"]}')


def main(argv=None):
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--version', action='version', version='astra-pkg 1')
	sub = parser.add_subparsers(dest='command', required=True)
	create = sub.add_parser('create', help='create a source-library package in a new directory')
	create.add_argument('directory', type=Path)
	create.add_argument('--name', required=True)
	create.add_argument('--compiler-version', required=True)
	create.add_argument('--license', required=True)
	for command in ('lock', 'build', 'install', 'list'):
		p = sub.add_parser(command)
		p.add_argument('--package', type=Path, default=Path.cwd())
		p.add_argument('--path', type=Path, action='append', default=[], help='explicit local dependency package root')
		p.add_argument('--prefix', type=Path, default=Path(__file__).resolve().parent.parent)
		sibling = Path(__file__).resolve().with_name('astrac')
		p.add_argument('--compiler', default=str(sibling) if sibling.is_file() else shutil.which('astrac') or 'astrac')
		if command == 'build':
			p.add_argument('-o', '--output', type=Path, required=True)
			p.add_argument('-O', choices=('0', '1', '2'), default='0')
			p.add_argument('-g', action='store_true')
	args = parser.parse_args(argv)
	try:
		if args.command == 'create':
			require(NAME.fullmatch(args.name), 'invalid package name')
			require(VERSION.fullmatch(args.compiler_version), 'invalid compiler version')
			require(0 < len(args.license) <= 200, 'explicit license required')
			root = safe_absolute(args.directory)
			root.mkdir()
			(root / 'library.astra').write_text('// Add public library declarations here.\n')
			exclusive_json(root / MANIFEST, {'format': FORMAT, 'name': args.name, 'version': '0.1.0',
				'compiler': args.compiler_version, 'abi': 'source+native-unit/1', 'license': args.license,
				'sources': ['library.astra'], 'dependencies': {}})
			return 0
		compiler, identity = compiler_identity(args.compiler)
		root, order, lock = resolve(args.package, args.path, safe_absolute(args.prefix), identity)
		lock_path = safe_absolute(root.root / LOCK)
		if args.command == 'lock':
			if lock_path.exists():
				require(read_json(lock_path) == lock, 'lock differs; review changes and explicitly remove old lock before relocking')
			else:
				exclusive_json(lock_path, lock)
			print('locked ' + ', '.join(p.data['name'] + '@' + p.data['version'] for p in order))
			return 0
		require(read_json(lock_path) == lock, 'lock/integrity/compiler mismatch; review the changed package inputs')
		if args.command == 'list':
			for p in order:
				print(f'{p.data["name"]}@{p.data["version"]} {digest(encoded(p.files))}')
		elif args.command == 'install':
			install(order, safe_absolute(args.prefix), lock)
		else:
			output = safe_absolute(args.output)
			require(not output.exists(), 'build output already exists; choose a new path')
			for p in order:
				require(not output.is_relative_to(p.root), 'build output must be outside every source package')
			command = [str(compiler), '-O' + args.O] + (['-g'] if args.g else [])
			for p in order:
				command += [str(member(p.root, n)) for n in p.data['sources']]
				for role, flag in (('vapi', '--vapi'), ('native_modules', '--import-module')):
					for n in p.data.get(role, []):
						command += [flag, str(member(p.root, n))]
			for p in reversed(order):
				for n in p.data.get('objects', []):
					command += ['--link-object', str(member(p.root, n))]
				for n in p.data.get('libraries', []):
					command += ['--link-library', n]
			command += ['-o', str(output)]
			result = subprocess.run(command)
			require(result.returncode == 0, f'compiler exited {result.returncode}')
		return 0
	except (PackageError, OSError, ValueError, UnicodeError, TypeError, RecursionError,
		subprocess.SubprocessError) as error:
		print(f'astra-pkg: error: {error}', file=sys.stderr)
		return 1


if __name__ == '__main__':
	raise SystemExit(main())
