#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless line/token chunk transport; logical files retain exact SHA and mode."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import tarfile
import tempfile
import time


def digest(raw):
	return hashlib.sha256(raw).hexdigest()


def safe(name):
	p = PurePosixPath(name)
	assert name and not p.is_absolute() and '..' not in p.parts and str(p) == name
	return p


class ChunkWriter:
	def __init__(self, tar):
		self.tar, self.chunks, self.small = tar, {}, {}

	def put(self, raw):
		key = digest(raw)
		if key not in self.chunks:
			ordinal = len(self.chunks) + 1
			entry = tarfile.TarInfo('CHUNKS/'+str(ordinal).zfill(8)); entry.size = len(raw); entry.mode = 0o644
			self.tar.addfile(entry, io.BytesIO(raw)); self.chunks[key] = ordinal
		return self.chunks[key]

	def pieces(self, stream, name):
		if Path(name).suffix not in {'.json', '.stdout', '.stderr', '.ll', '.log', '.txt', '.csv', '.md'}:
			while raw := stream.read(65536): yield raw
			return
			# Stable top-level JSON and row-family boundaries keep unchanged source
			# observations shared even when earlier type numbers change byte lengths.
		buffer, lines, previous = [], 0, None
		for line in stream:
			family = line.partition(b' ')[0]
			anchor = line.startswith(b'  "') if name.endswith('.json') else family != previous
			if buffer and (anchor or lines >= (256 if name.endswith('.json') else 32)):
				yield b''.join(buffer); buffer, lines = [], 0
			previous = family
			if len(line) > 262144:
				if buffer: yield b''.join(buffer); buffer, lines = [], 0
				# Actual LLVM mutation snapshots are long whitespace-separated hex
				# tokens. Preserve every separator while sharing exact valid twins.
				for match in re.finditer(rb'\S+|\s+', line): yield match.group()
			else: buffer.append(line); lines += 1
		if buffer: yield b''.join(buffer)

	def add(self, name, path, raw, mode, expected):
		safe(name); size = path.stat().st_size if path else len(raw)
		row = dict(archive_path=name, bytes=size, mode=mode, sha256=expected)
		if size >= 1048576:
			stream = path.open('rb') if path else io.BytesIO(raw)
			try:
				ids = []; observed = hashlib.sha256(); count = 0
				for piece in self.pieces(stream, name):
					observed.update(piece); count += len(piece); ids.append(self.put(piece))
				assert count == size and observed.hexdigest() == expected
				row['chunk_ids'] = ids
			finally: stream.close()
		else:
			entry = tarfile.TarInfo(name); entry.mode = mode; key = (expected, mode)
			if key in self.small:
				entry.type = tarfile.LNKTYPE; entry.linkname = self.small[key]; self.tar.addfile(entry)
			else:
				entry.size = size
				stream = path.open('rb') if path else io.BytesIO(raw)
				try: self.tar.addfile(entry, stream)
				finally: stream.close()
				self.small[key] = name
		return row


def verify(archive, output=None):
	started = time.monotonic(); regular, chunks = {}, {}; index = None
	if output:
		assert not output.exists(); output.mkdir(parents=True)
	with tempfile.TemporaryDirectory(prefix='verify-chunks-', dir=archive.parent) as temporary:
		cache = Path(temporary)
		with tarfile.open(archive, 'r|xz') as tar:
			for entry in tar:
				safe(entry.name); assert entry.mode & ~0o777 == 0
				if entry.islnk():
					assert entry.linkname in regular and regular[entry.linkname]['mode'] == entry.mode
					regular[entry.name] = dict(regular[entry.linkname])
					if output:
						p = output/entry.name; p.parent.mkdir(parents=True, exist_ok=True); os.link(output/entry.linkname, p)
					continue
				assert entry.isfile(); source = tar.extractfile(entry)
				if entry.name == 'ARCHIVE-INDEX.json':
					assert index is None; index = json.loads(source.read()); continue
				match = re.fullmatch(r'CHUNKS/(\d{8})', entry.name)
				if match:
					ordinal = int(match[1]); assert ordinal not in chunks
					path = cache/str(ordinal); chunks[ordinal] = path
				else:
					assert entry.name not in regular; path = output/entry.name if output else None
					if path: path.parent.mkdir(parents=True, exist_ok=True)
				writer = path.open('xb') if path else None; observed = hashlib.sha256(); size = 0
				try:
					while raw := source.read(1048576):
						observed.update(raw); size += len(raw)
						if writer: writer.write(raw)
				finally:
					if writer: writer.close(); os.chmod(path, entry.mode)
				assert size == entry.size
				if not match: regular[entry.name] = dict(bytes=size, mode=entry.mode, sha256=observed.hexdigest())
		assert index is not None and index['storage_format'] == 'astra-line-chunk/1'
		logical = {row['archive_path']:row for row in index['files'] if 'bytes' in row}; used = set()
		for name, row in logical.items():
			safe(name); assert row['mode'] & ~0o777 == 0
			if 'chunk_ids' not in row:
				assert name in regular and all(regular[name][key] == row[key] for key in ('bytes', 'mode', 'sha256')), name
				continue
			assert name not in regular; observed = hashlib.sha256(); size = 0
			path = output/name if output else None
			if path: path.parent.mkdir(parents=True, exist_ok=True)
			writer = path.open('xb') if path else None
			try:
				for ordinal in row['chunk_ids']:
					assert ordinal in chunks; used.add(ordinal)
					with chunks[ordinal].open('rb') as stream:
						while raw := stream.read(1048576):
							observed.update(raw); size += len(raw)
							if writer: writer.write(raw)
			finally:
				if writer: writer.close(); os.chmod(path, row['mode'])
			assert size == row['bytes'] and observed.hexdigest() == row['sha256'], name
		assert used == chunks.keys() and regular.keys() == {name for name,row in logical.items() if 'chunk_ids' not in row}
	with archive.open('rb') as stream: archive_sha = hashlib.file_digest(stream, 'sha256').hexdigest()
	return dict(status='PASS', logical_files=len(logical), unique_chunks=len(chunks), logical_bytes=sum(row['bytes'] for row in logical.values()), archive_sha256=archive_sha, seconds=time.monotonic()-started, final_commit=index['final_commit'], final_tree=index['final_tree'])


def main():
	p = argparse.ArgumentParser(); p.add_argument('archive', type=Path); p.add_argument('--output', type=Path); p.add_argument('--receipt', type=Path); a = p.parse_args()
	result = verify(a.archive, a.output)
	if a.receipt: a.receipt.write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(result))


if __name__ == '__main__':
	main()
