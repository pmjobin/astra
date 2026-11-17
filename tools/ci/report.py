#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Transport campaign evidence within the unchanged installed publisher's limits."""
import argparse
import base64
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import tarfile
import zipfile

from common import external, identify, require, sha, write


def verify_transport(data, transport):
	require(len(data) == transport['archive']['bytes'] and hashlib.sha256(data).hexdigest() == transport['archive']['sha256'], 'transport archive mismatch')
	with tarfile.open(fileobj=io.BytesIO(data), mode='r:xz') as archive:
		members = archive.getmembers()
		require(all(row.isfile() and row.size <= 128*1024**2 for row in members), 'unexpected transport member')
		index = json.load(archive.extractfile('INDEX.json'))
		expected = {'INDEX.json'} | {row['blob'] for row in index['files'].values()}
		require(len(members) == len(expected) and set(row.name for row in members) == expected, 'transport member inventory mismatch')
		blobs = {}
		for row in members:
			if row.name == 'INDEX.json':
				continue
			value = archive.extractfile(row).read()
			digest = hashlib.sha256(value).hexdigest()
			require(row.name == 'blobs/'+digest, 'blob content mismatch')
			blobs[row.name] = dict(bytes=len(value), sha256=digest)
		for name, row in index['files'].items():
			require(not Path(name).is_absolute() and '..' not in Path(name).parts, 'unsafe logical name')
			require(blobs[row['blob']] == dict(bytes=row['bytes'], sha256=row['sha256']), 'logical mapping mismatch')
	return dict(logical_files=len(index['files']), blobs=len(blobs), excluded=len(index['excluded']))


def verify_report(path):
	with zipfile.ZipFile(path) as archive:
		transport = json.loads(archive.read('evidence/TRANSPORT.json'))
		pieces = []
		for number, row in enumerate(transport['parts']):
			data = archive.read('evidence/'+row['path'])
			require(len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256'], 'part mismatch')
			part = json.loads(data)
			require(part['format'] == 'astra-byte-transport/1' and part['ordinal'] == number, 'part order mismatch')
			raw = base64.b64decode(part['base64'], validate=True)
			require(len(raw) == row['decoded_bytes'], 'decoded part length mismatch')
			pieces.append(raw)
		return verify_transport(b''.join(pieces), transport)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--verify', type=Path, help='Reopen an installed report without extracting or executing its contents')
	for name in ('campaign', 'qualification', 'engineering', 'seed', 'output'):
		p.add_argument('--'+name, type=Path)
	a = p.parse_args()
	if a.verify:
		print(json.dumps(verify_report(a.verify)))
		return
	require(all(getattr(a, name) for name in ('campaign', 'qualification', 'engineering', 'seed', 'output')), 'missing report input')
	output = external(a.output)
	qualification = json.loads(a.qualification.read_text())
	require(qualification['status'] == 'PARTIAL', 'this campaign has open native Windows and hosted gates')
	files, blobs, excluded = {}, {}, []
	def retain(path, logical):
		if path.is_symlink():
			data = (json.dumps(dict(kind='INERT_SYMLINK_OBSERVATION', target=os.readlink(path)), sort_keys=True)+'\n').encode()
			logical += '.symlink.json'
		else:
			data = path.read_bytes()
			require(hashlib.sha256(data).hexdigest() == sha(path), 'evidence changed during collection')
		digest = hashlib.sha256(data).hexdigest()
		require(logical not in files, 'duplicate logical path')
		files[logical] = dict(bytes=len(data), sha256=digest, blob='blobs/'+digest)
		blobs[digest] = data
	for directory, names, leaves in os.walk(a.campaign, followlinks=False):
		directory = Path(directory)
		for name in list(names):
			path = directory/name
			if path == output or path == a.campaign/'containers' or name.endswith('-profile'):
				names.remove(name)
				excluded.append(dict(path=str(path), reason='Publication output, private container engine state or browser profile; not execution evidence'))
			elif path.is_symlink():
				names.remove(name)
				retain(path, 'runtime/'+str(path.relative_to(a.campaign)))
		for name in sorted(leaves):
			path = directory/name
			if name.startswith('vgcore.') and path.suffix != '.json':
				excluded.append(dict(**identify(path), reason='Large generated failure core retained locally; raw failure commands and diagnostics included'))
			elif path.is_file() or path.is_symlink():
				retain(path, 'runtime/'+str(path.relative_to(a.campaign)))
	seed = json.loads(a.seed.read_text())['artifact']
	require(sha(seed['path']) == seed['sha256'], 'seed capsule changed')
	retain(Path(seed['path']), 'artifacts/'+Path(seed['path']).name)
	artifacts = [seed]
	for kind, row in qualification['packages'].items():
		artifact = row['artifact']
		require(sha(artifact['path']) == artifact['sha256'], 'installer changed')
		artifacts.append(dict(**artifact, kind=kind, transport='LOCAL_FILE_NOT_EMBEDDED', reason='Each native installer exceeds the unchanged installed publisher 25 MiB ZIP cap'))
		for name in ('usr/lib/astra/astrac.native', 'usr/lib/astra/astrac.doc', 'usr/lib/astra/llvm/libLLVM.so.23.1'):
			artifacts.append(dict(**identify(Path(artifact['path']).parent/'payload'/name), kind=kind, transport='LOCAL_GENERATED_FILE_NOT_EMBEDDED'))
	index = dict(format='astra-installer-evidence/1', files=files, excluded=excluded, generated_artifacts=artifacts, scope='Lossless raw campaign observations including failed attempts. Container state and large generated binaries remain external with identities. Links are inert metadata; no archive member is executed.')
	archive_path = output/'transport.tar.xz'
	with tarfile.open(archive_path, 'w:xz', preset=6, format=tarfile.PAX_FORMAT) as archive:
		def add(name, data):
			info = tarfile.TarInfo(name)
			info.size, info.mode, info.mtime = len(data), 0o444, 0
			archive.addfile(info, io.BytesIO(data))
		add('INDEX.json', (json.dumps(index, sort_keys=True, indent=2)+'\n').encode())
		for digest, data in sorted(blobs.items()):
			add('blobs/'+digest, data)
	data = archive_path.read_bytes()
	parts = []
	for number, offset in enumerate(range(0, len(data), 1200000)):
		part = output/('transport-'+str(number).zfill(2)+'.json')
		raw = data[offset:offset+1200000]
		write(part, dict(format='astra-byte-transport/1', ordinal=number, base64=base64.b64encode(raw).decode()))
		parts.append(dict(path=part.name, bytes=part.stat().st_size, sha256=sha(part), decoded_bytes=len(raw)))
	transport = dict(format='astra-installer-evidence-transport/1', archive=identify(archive_path), parts=parts, logical_files=len(files), blobs=len(blobs), generated_artifacts=artifacts, excluded=excluded)
	verification = verify_transport(data, transport)
	write(output/'TRANSPORT.json', transport)
	shutil.copyfile(a.qualification, output/'QUALIFICATION.json')
	shutil.copyfile(a.engineering, output/'ENGINEERING.md')
	shutil.copyfile(Path(__file__), output/'report.py.txt')
	write(output/'ARTIFACTS.json', dict(artifacts=artifacts, public_release=False, seed_distributed=False))
	attachments = []
	for path in sorted(output.iterdir()):
		if path.suffix not in ('.json', '.md', '.txt'):
			continue
		require(path.stat().st_size <= 2*1024**2, 'installed publisher per-file limit exceeded')
		attachments.append(dict(path=path.name, bytes=path.stat().st_size, sha256=sha(path)))
	require(len(attachments) <= 128 and sum(row['bytes'] for row in attachments) <= 64*1024**2, 'installed publisher evidence limits exceeded')
	write(output/'evidence-index.json', dict(format='pm-next-evidence/1', files=attachments))
	print(json.dumps(dict(**verification, archive_bytes=len(data), archive_sha256=sha(archive_path), parts=len(parts), attachments=len(attachments))))


if __name__ == '__main__':
	main()
