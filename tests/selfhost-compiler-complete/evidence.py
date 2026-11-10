#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless content-addressed task evidence; reconstruction executes no evidence."""
import argparse
import hashlib
import io
import json
import lzma
from pathlib import Path, PurePosixPath
import stat
import tarfile
import tempfile
import time

from columns import encode, reconstruct


def sha(path):
	with Path(path).open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def safe(name):
	parts = name.split('/')
	assert name and not name.startswith('/') and '\\' not in name
	assert all(part not in ('', '.', '..', '.git') for part in parts)
	assert all(ord(char) >= 32 for char in name)
	return PurePosixPath(name)


def pack(roots, output, runtime):
	assert not output.exists()
	files = {}
	blobs = {}
	for specification in roots:
		label, directory = specification.split('=', 1)
		assert safe(label).name == label
		requested = Path(directory)
		assert requested.is_absolute() and all(not entry.is_symlink() for entry in (requested, *requested.parents))
		root = requested.resolve(strict=True)
		assert root.is_dir() and not output.resolve().is_relative_to(root)
		for path in sorted(root.rglob('*')):
			assert not path.is_symlink(), path
			if path.is_dir():
				continue
			assert path.is_file() and stat.S_ISREG(path.stat().st_mode)
			name = label+'/'+str(path.relative_to(root))
			safe(name)
			assert name not in files
			before = path.stat()
			digest = sha(path)
			after = path.stat()
			assert (before.st_ino, before.st_size, before.st_mtime_ns) == (after.st_ino, after.st_size, after.st_mtime_ns)
			blob = 'blobs/'+digest
			files[name] = dict(bytes=after.st_size, sha256=digest, blob=blob, mode=oct(stat.S_IMODE(after.st_mode)), mtime_ns=after.st_mtime_ns)
			blobs.setdefault(blob, path)
	model = dict(format='astra-compiler-complete26-evidence/2', files=files, columns={})
	filters = [dict(id=lzma.FILTER_LZMA2, preset=6, dict_size=256*1024*1024)]
	with tempfile.TemporaryDirectory(prefix='encode-columns-', dir=runtime) as temporary:
		payload = {}
		for name, path in blobs.items():
			if path.stat().st_size >= 2*1024*1024 and path.name.endswith(('-ledger.stdout', '-trace.stdout')):
				directory = Path(temporary)/name[6:]
				directory.mkdir()
				row = encode(path, directory, name, 0)
				assert row['sha256'] == name[6:]
				model['columns'][name] = row
				for part in directory.iterdir():
					payload['columns/'+name[6:]+'/'+part.name] = part
			else:
				payload[name] = path
		def ordering(item):
			name, path = item
			if path.name.endswith('-nodes.jsonl'): return (0, path.stat().st_size, name)
			if name.startswith('columns/'): return (1, path.name, name)
			return (2, path.suffix, name)
		with lzma.LZMAFile(output, 'wb', filters=filters) as compressed, tarfile.open(fileobj=compressed, mode='w|') as archive:
			for name, path in sorted(payload.items(), key=ordering):
				if name.startswith('blobs/'): assert sha(path) == name[6:]
				entry = tarfile.TarInfo(name)
				entry.size = path.stat().st_size
				entry.mode = 0o644
				with path.open('rb') as stream:
					archive.addfile(entry, stream)
			data = (json.dumps(model, separators=(',', ':'))+'\n').encode()
			entry = tarfile.TarInfo('INDEX.json')
			entry.size = len(data)
			entry.mode = 0o644
			archive.addfile(entry, io.BytesIO(data))
	return dict(files=len(files), blobs=len(blobs), column_encoded_blobs=len(model['columns']), original_bytes=sum(row['bytes'] for row in files.values()), archive_bytes=output.stat().st_size, archive_sha256=sha(output))


def verify(archive, runtime):
	with tempfile.TemporaryDirectory(prefix='verify-evidence-', dir=runtime) as temporary:
		root = Path(temporary)
		observed = {}
		model = None
		with tarfile.open(archive, 'r|xz') as packed:
			for member in packed:
				assert member.isfile() and member.name not in observed
				stream = packed.extractfile(member)
				if member.name == 'INDEX.json':
					assert model is None
					model = json.load(stream)
					continue
				safe(member.name)
				parts = member.name.split('/')
				assert parts[0] in ('blobs', 'columns') and len(parts[1]) == 64
				assert all(char in '0123456789abcdef' for char in parts[1])
				assert len(parts) == (2 if parts[0] == 'blobs' else 3)
				path = root/member.name
				path.parent.mkdir(parents=True, exist_ok=True)
				with path.open('xb') as out:
					for block in iter(lambda: stream.read(1048576), b''):
						out.write(block)
				assert path.stat().st_size == member.size
				if parts[0] == 'blobs': assert sha(path) == parts[1]
				observed[member.name] = member.size
		assert model['format'] in ('astra-compiler-complete26-evidence/1', 'astra-compiler-complete26-evidence/2')
		column_parts = set()
		for name, row in model.get('columns', {}).items():
			assert name == row['path'] == 'blobs/'+row['sha256'] and name not in observed
			assert len(row['sha256']) == 64 and all(char in '0123456789abcdef' for char in row['sha256'])
			directory = root/'columns'/row['sha256']
			parts = [*row['parts'].values(), *(part for group in row['groups'] for part in group['columns'])]
			for part in parts:
				assert Path(part['path']).name == part['path']
				key = 'columns/'+row['sha256']+'/'+part['path']
				assert key in observed and key not in column_parts
				column_parts.add(key)
			path = root/name
			path.parent.mkdir(exist_ok=True)
			with path.open('xb') as out:
				for raw in reconstruct(directory, row): out.write(raw)
			assert path.stat().st_size == row['bytes'] and sha(path) == row['sha256']
			observed[name] = row['bytes']
		assert column_parts == {name for name in observed if name.startswith('columns/')}
		assert {row['blob'] for row in model['files'].values()} == {name for name in observed if name.startswith('blobs/')}
		for name, row in model['files'].items():
			safe(name)
			assert row['blob'] == 'blobs/'+row['sha256'] and observed[row['blob']] == row['bytes']
		return dict(status='BYTE_EXACT', logical_files=len(model['files']), unique_blobs=sum(name.startswith('blobs/') for name in observed), column_encoded_blobs=len(model.get('columns', {})), archive_sha256=sha(archive), classification='Complete byte reconstruction only; no recorded executable is run or qualified.')


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('mode', choices=('pack', 'verify'))
	p.add_argument('--root', action='append', default=[], help='LABEL=/absolute/task/root')
	p.add_argument('--archive', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--receipt', type=Path, required=True)
	a = p.parse_args()
	assert a.archive.is_absolute() and a.runtime.is_absolute() and a.runtime.is_dir()
	start = time.monotonic()
	result = pack(a.root, a.archive, a.runtime) if a.mode == 'pack' else verify(a.archive, a.runtime)
	result['seconds'] = time.monotonic()-start
	a.receipt.write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(result), flush=True)


if __name__ == '__main__':
	main()
