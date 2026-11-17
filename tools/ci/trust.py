#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Authenticate inputs before extraction or execution. No host compiler fallback."""
import argparse
import json
from pathlib import Path, PurePosixPath
import platform
import re
import subprocess
import tarfile
import urllib.request

from common import external, require, sha, verify, write


def host(manifest):
	require(platform.system() == manifest['os'] and platform.machine().lower() in manifest['machines'], 'unsupported seed OS/architecture')


def seed_manifest(path):
	manifest = json.loads(Path(path).read_text())
	required = {'format', 'id', 'os', 'machines', 'target', 'abi', 'bytes', 'sha256', 'url', 'distribution_status', 'license', 'source_commit', 'source_tree', 'recipe', 'provenance', 'producer', 'runtime', 'owner_root_disposition', 'windows'}
	require(set(manifest) == required and manifest['format'] == 'astra-seed/1', 'incomplete or unsupported seed trust manifest')
	require(isinstance(manifest['bytes'], int) and manifest['bytes'] > 0 and re.fullmatch('[0-9a-f]{64}', manifest['sha256']), 'invalid seed identity')
	require(all(re.fullmatch('[0-9a-f]{40}', manifest[key]) for key in ('source_commit', 'source_tree')), 'seed source identity missing')
	require(manifest['abi'] == 'E25-A-v1' and manifest['license'] and manifest['recipe'] and manifest['producer'] and manifest['runtime'] and manifest['owner_root_disposition'], 'seed provenance fields missing')
	require(all(re.fullmatch('[0-9a-f]{64}', manifest['provenance'][key]) for key in ('report_sha256', 'stage_receipt_sha256')), 'seed provenance receipts missing')
	host(manifest)
	return manifest


def fetch(pin, output):
	url = pin.get('url')
	require(isinstance(url, str) and url.startswith('https://') and not any(x in url for x in ('/latest/', '/heads/')), 'authenticated distribution URL unavailable')
	output = Path(output)
	require(not output.exists(), 'download destination already exists; authenticate caches explicitly')
	partial = output.with_name(output.name+'.partial')
	with urllib.request.urlopen(url, timeout=60) as response, partial.open('xb') as stream:
		require(response.url.startswith('https://'), 'insecure download redirect')
		count = 0
		while chunk := response.read(1024*1024):
			count += len(chunk)
			require(count <= pin['bytes'], 'download exceeds pinned length')
			stream.write(chunk)
	verify(partial, pin)
	partial.replace(output)
	return output


def extract(archive, destination, max_bytes=14*1024**3):
	"""Validate the whole namespace, then use Python's restrictive data filter."""
	destination = Path(destination)
	require(not destination.exists(), 'extraction destination exists')
	with Path(archive).open('rb') as stream:
		zstandard = stream.read(4) == b'\x28\xb5\x2f\xfd'
	if zstandard:
		# The official archive uses a window larger than Python's default decoder.
		# Bound decompressed bytes explicitly and retain any interrupted output.
		unpacked = destination.with_name(destination.name+'.tar')
		with unpacked.open('xb') as stream:
			process = subprocess.Popen(['zstd', '-d', '--long=31', '--stdout', str(archive)], stdout=subprocess.PIPE)
			try:
				count = 0
				while chunk := process.stdout.read(1024*1024):
					count += len(chunk)
					require(count <= max_bytes, 'expanded archive exceeds budget')
					stream.write(chunk)
				require(process.wait() == 0, 'zstd decompression failed')
			finally:
				if process.poll() is None:
					process.kill()
					process.wait()
				process.stdout.close()
		archive = unpacked
	with tarfile.open(archive, 'r:*') as packed:
		members = packed.getmembers()
		seen = set()
		links = set()
		total = 0
		for item in members:
			name = item.name.rstrip('/')
			path = PurePosixPath(name)
			require(name and not path.is_absolute() and '..' not in path.parts and '\\' not in name and name == str(path), 'unsafe archive path')
			require(name not in seen, 'duplicate archive path')
			seen.add(name)
			require(item.isfile() or item.isdir() or item.issym(), 'unsupported archive member')
			if item.issym():
				links.add(path)
				require(not PurePosixPath(item.linkname).is_absolute() and '\\' not in item.linkname, 'unsafe archive link')
				resolved = (destination/path.parent/item.linkname).resolve()
				require(resolved.is_relative_to(destination.resolve()), 'archive link escapes destination')
			total += item.size
			require(total <= max_bytes, 'expanded archive exceeds budget')
		for name in seen:
			require(not any(parent in links for parent in PurePosixPath(name).parents), 'archive writes through a symlink')
		destination.mkdir(parents=True)
		packed.extractall(destination, filter='data')
	return destination


def extract_selected(archive, destination, pins, archive_root):
	"""Stream the upstream archive but install only independently pinned members."""
	destination = Path(destination)
	require(not destination.exists() and pins, 'selected extraction requires fresh output and pins')
	destination.mkdir(parents=True)
	process = subprocess.Popen(['zstd', '-d', '--long=31', '--stdout', str(archive)], stdout=subprocess.PIPE)
	seen, selected, links = set(), set(), set()
	expanded = 0
	try:
		with tarfile.open(fileobj=process.stdout, mode='r|') as packed:
			for member in packed:
				name = member.name.rstrip('/')
				path = PurePosixPath(name)
				require(name and not path.is_absolute() and '..' not in path.parts and '\\' not in name and name == str(path), 'unsafe archive path')
				require(name not in seen, 'duplicate archive path')
				seen.add(name)
				require(member.isfile() or member.isdir() or member.issym(), 'unsupported archive member')
				if member.issym():
					links.add(path)
					require(not PurePosixPath(member.linkname).is_absolute() and '\\' not in member.linkname and (destination/path.parent/member.linkname).resolve().is_relative_to(destination.resolve()), 'unsafe archive link')
				expanded += member.size
				require(expanded <= 14*1024**3, 'expanded archive exceeds budget')
				prefix = archive_root+'/'
				key = name[len(prefix):] if name.startswith(prefix) else None
				if key not in pins:
					continue
				require(member.isfile() and member.size == pins[key]['bytes'], 'selected archive member mismatch')
				out = destination/key
				out.parent.mkdir(parents=True, exist_ok=True)
				with packed.extractfile(member) as source, out.open('xb') as target:
					while chunk := source.read(1024*1024):
						target.write(chunk)
				out.chmod(0o755 if key.startswith('bin/') else 0o644)
				verify(out, pins[key])
				selected.add(key)
		process.stdout.close()
		require(process.wait() == 0, 'zstd decompression failed')
		require(selected == set(pins), 'selected toolchain member missing')
		require(not any(parent in links for name in seen for parent in PurePosixPath(name).parents), 'archive writes through a symlink')
	finally:
		if process.poll() is None:
			process.kill()
			process.wait()
		process.stdout.close()
	return destination


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--manifest', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	p.add_argument('--archive', type=Path)
	a = p.parse_args()
	manifest = json.loads(a.manifest.read_text())
	require(manifest['format'] == 'astra-toolchain/1' and manifest['version'] == '23.1.4', 'unsupported toolchain manifest')
	host(manifest)
	output = external(a.output)
	pin = manifest['archive']
	archive = verify(a.archive, pin) if a.archive else fetch(pin, output/'toolchain.tar.xz')
	if manifest.get('files'):
		extract_selected(archive, output/'unpacked', manifest['files'], 'LLVM-23.1.4-Linux-X64')
	else:
		extract(archive, output/'unpacked')
	write(output/'verified.json', dict(manifest_sha256=sha(a.manifest), archive_sha256=sha(archive), status='AUTHENTICATED_INPUT_NOT_QUALIFICATION'))
	print(output/'unpacked')


if __name__ == '__main__':
	main()
