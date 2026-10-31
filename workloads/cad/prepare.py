#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify local CAD authorities and extract exact sources; never fetch inputs."""
import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
PINS = Path(__file__).with_name('pins.json')
ENV = dict(os.environ, GIT_OPTIONAL_LOCKS='0', PYTHONDONTWRITEBYTECODE='1', CCACHE_DISABLE='1')


class BlockedInput(Exception):
	pass


def sha256(path):
	with path.open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def git(repository, *args):
	command = ['git', '-C', str(repository), *args]
	p = subprocess.run(command, capture_output=True, env=ENV)
	if p.returncode:
		raise BlockedInput(f'{command!r}: {p.stderr.decode(errors="backslashreplace").strip()}')
	return p.stdout


def verify_repository(repository, pin):
	actual = git(repository, 'rev-parse', '--verify', pin['revision'] + '^{commit}').decode().strip()
	if actual != pin['revision']:
		raise BlockedInput(f'{repository}: expected exact commit {pin["revision"]}; got {actual}')
	tree = git(repository, 'rev-parse', actual + '^{tree}').decode().strip()
	if tree != pin['tree']:
		raise BlockedInput(f'{repository}: tree {tree} differs from {pin["tree"]}')
	return {'repository': str(repository), 'revision': actual, 'tree': tree}


def git_members(repository, revision):
	result = {}
	for raw in git(repository, 'ls-tree', '-rz', '--full-tree', revision).split(b'\0'):
		if not raw:
			continue
		head, name = raw.split(b'\t', 1)
		mode, kind, blob = head.decode().split()
		if kind != 'blob' or mode not in {'100644', '100755'}:
			raise BlockedInput(f'{revision}: unsupported member {name!r} ({mode}, {kind})')
		result[name.decode()] = {'mode': mode, 'git_blob': blob}
	return result


def extract_exact(repository, pin, destination, archive):
	if destination.exists() or archive.exists():
		raise BlockedInput(f'refusing to reuse an existing extraction/archive: {destination}, {archive}')
	members = git_members(repository, pin['revision'])
	archive.write_bytes(git(repository, '-c', 'tar.umask=0022', 'archive', '--format=tar', pin['revision']))
	seen = {}
	with tarfile.open(archive) as source:
		for member in source:
			if member.isdir():
				continue
			name = member.name
			path = PurePosixPath(name)
			if path.is_absolute() or '..' in path.parts or not member.isfile() or name not in members or name in seen:
				raise BlockedInput(f'invalid archive member: {name}')
			data = source.extractfile(member).read()
			row = members[name]
			blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
			if row['git_blob'] != blob or member.mode != int(row['mode'][-3:], 8):
				raise BlockedInput(f'archive blob/mode mismatch: {name}')
			seen[name] = dict(row, bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
			output = destination / name
			output.parent.mkdir(parents=True, exist_ok=True)
			output.write_bytes(data)
			output.chmod(member.mode)
	if set(seen) != set(members):
		raise BlockedInput('archive member set differs from the pinned Git tree')
	return {'archive_sha256': sha256(archive), 'members': seen}


def check_assets(directory, assets):
	rows = []
	for asset in assets:
		path = directory / asset['file']
		if not path.is_file():
			raise BlockedInput(f'missing local-only asset {path}; expected SHA-256 {asset["sha256"]}')
		digest = sha256(path)
		if digest != asset['sha256']:
			raise BlockedInput(f'asset {path}: SHA-256 {digest}; expected {asset["sha256"]}')
		rows.append(dict(asset, path=str(path), bytes=path.stat().st_size))
	return rows


def check_dependencies():
	rows = []
	for program in ['git', 'meson', 'ninja', 'valac', 'gcc', 'llvm-config', 'pkg-config', 'python3']:
		path = shutil.which(program)
		if path is None:
			raise BlockedInput(f'missing existing application/build dependency: {program}')
		rows.append({'program': program, 'path': path})
	for module in ['numpy', 'Pillow']:
		try:
			version = importlib.metadata.version(module)
		except importlib.metadata.PackageNotFoundError as error:
			raise BlockedInput(f'missing existing oracle dependency: {module}') from error
		rows.append({'python_package': module, 'version': version})
	for package in ['libpng', 'glib-2.0', 'gobject-2.0']:
		p = subprocess.run(['pkg-config', '--modversion', package], capture_output=True, text=True, env=ENV)
		if p.returncode:
			raise BlockedInput(f'missing existing native dependency {package}: {p.stderr.strip()}')
		rows.append({'pkg_config': package, 'version': p.stdout.strip()})
	return rows


def prepare(args):
	pins = json.loads(PINS.read_text())
	out = args.output.resolve()
	allowed = ROOT / 'build/app-cad-1'
	if not out.is_relative_to(allowed) or out == allowed:
		raise BlockedInput(f'output must be a fresh child of {allowed}')
	if out.exists():
		raise BlockedInput(f'output already exists: {out}; use a fresh campaign child')
	out.mkdir(parents=True)
	record = {'status': 'BLOCKED_INPUT', 'qualification': 'NOT_RUN', 'checks': [], 'missing': []}
	try:
		repositories = {'current': args.compiler_repository.resolve(), 'historical-compiler': args.compiler_repository.resolve(), 'cad': args.cad_repository.resolve()}
		for name, repository in repositories.items():
			record['checks'].append(dict(label=name, **verify_repository(repository, pins[name])))
		report_repo = args.cad_repository.resolve()
		verify_repository(report_repo, pins['historical-report'])
		for name, item in pins['historical-report']['files'].items():
			data = git(report_repo, 'show', pins['historical-report']['revision'] + ':' + name)
			if hashlib.sha256(data).hexdigest() != item['sha256']:
				raise BlockedInput(f'historical report hash mismatch: {name}')
			path = out / 'references' / Path(name).name
			path.parent.mkdir(exist_ok=True)
			path.write_bytes(data)
		record['assets'] = check_assets(args.assets.resolve(), pins['assets'])
		record['dependencies'] = check_dependencies()
		if args.extract:
			(out / 'archives').mkdir()
			(out / 'sources').mkdir()
			for name, repository in repositories.items():
				result = extract_exact(repository, pins[name], out / 'sources' / name, out / 'archives' / (name + '.tar'))
				(out / (name + '-members.json')).write_text(json.dumps(result, indent='\t') + '\n')
			(out / 'assets').mkdir()
			for row in record['assets']:
				destination = out / 'assets' / row['file']
				shutil.copyfile(row['path'], destination)
				if sha256(destination) != row['sha256']:
					raise BlockedInput(f'local copy changed: {destination}')
		record['status'] = 'INPUTS_VERIFIED'
	except (BlockedInput, OSError) as error:
		record['missing'].append(str(error))
	finally:
		(out / 'preflight.json').write_text(json.dumps(record, indent='\t') + '\n')
	print(json.dumps({'status': record['status'], 'qualification': record['qualification'], 'record': str(out / 'preflight.json'), 'missing': record['missing']}, indent='\t'))
	return 2 if record['missing'] else 0


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler-repository', type=Path, default=ROOT)
	parser.add_argument('--cad-repository', type=Path, required=True)
	parser.add_argument('--assets', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--extract', action='store_true', help='extract verified sources and local-only asset copies into the fresh output')
	return prepare(parser.parse_args())


if __name__ == '__main__':
	sys.exit(main())
