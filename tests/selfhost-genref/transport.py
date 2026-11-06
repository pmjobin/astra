#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify/restore astra-line-chunk/1 with one bounded disk spool for all chunks."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import tarfile
import tempfile
import time


def safe(name):
	p = PurePosixPath(name); assert name and not p.is_absolute() and '..' not in p.parts and str(p) == name; return p


def verify(archive, output=None):
	started = time.monotonic(); regular = {}; chunks = {}; index = None; seen = set()
	if output:
		assert not output.exists(); output.mkdir(parents=True)
	with tempfile.TemporaryFile(dir=archive.parent) as spool:
		with tarfile.open(archive, 'r|xz', stream=True) as packed:
			for entry in packed:
				safe(entry.name); assert entry.name not in seen and entry.mode & ~0o777 == 0; seen.add(entry.name)
				if entry.islnk():
					assert entry.linkname in regular and entry.mode == regular[entry.linkname]['mode']; regular[entry.name] = dict(regular[entry.linkname])
					if output:
						path = output/entry.name; path.parent.mkdir(parents=True, exist_ok=True); os.link(output/entry.linkname, path)
					continue
				assert entry.isfile(); source = packed.extractfile(entry)
				if entry.name == 'ARCHIVE-INDEX.json':
					assert index is None; index = json.loads(source.read()); continue
				match = re.fullmatch(r'CHUNKS/(\d{8})', entry.name); path = None; offset = spool.tell()
				if match:
					ordinal = int(match[1]); assert ordinal not in chunks
				elif output:
					path = output/entry.name; path.parent.mkdir(parents=True, exist_ok=True)
				writer = path.open('xb') if path else None; observed = hashlib.sha256(); size = 0
				try:
					while raw := source.read(1048576):
						observed.update(raw); size += len(raw)
						if match: spool.write(raw)
						if writer: writer.write(raw)
				finally:
					if writer: writer.close(); path.chmod(entry.mode)
				assert size == entry.size
				if match: chunks[ordinal] = (offset, size)
				else: regular[entry.name] = dict(bytes=size, mode=entry.mode, sha256=observed.hexdigest())
		assert index is not None and index['storage_format'] == 'astra-line-chunk/1'
		logical = {row['archive_path']:row for row in index['files']}; assert len(logical) == len(index['files']); used = set()
		for name, row in logical.items():
			safe(name); assert row['mode'] & ~0o777 == 0
			if 'chunk_ids' not in row:
				assert name in regular and all(regular[name][key] == row[key] for key in ('bytes', 'mode', 'sha256')), name; continue
			assert name not in regular; observed = hashlib.sha256(); size = 0; path = output/name if output else None
			if path: path.parent.mkdir(parents=True, exist_ok=True)
			writer = path.open('xb') if path else None
			try:
				for ordinal in row['chunk_ids']:
					assert ordinal in chunks; used.add(ordinal); offset, remaining = chunks[ordinal]; spool.seek(offset)
					while remaining:
						raw = spool.read(min(1048576, remaining)); assert raw; remaining -= len(raw); size += len(raw); observed.update(raw)
						if writer: writer.write(raw)
			finally:
				if writer: writer.close(); path.chmod(row['mode'])
			assert size == row['bytes'] and observed.hexdigest() == row['sha256'], name
		assert used == chunks.keys() and regular.keys() == {name for name, row in logical.items() if 'chunk_ids' not in row}
	with archive.open('rb') as stream: digest = hashlib.file_digest(stream, 'sha256').hexdigest()
	return dict(status='PASS', logical_files=len(logical), unique_chunks=len(chunks), logical_bytes=sum(row['bytes'] for row in logical.values()), archive_sha256=digest, seconds=time.monotonic()-started, final_commit=index['final_commit'], final_tree=index['final_tree'], classification='Exact byte transport verification; not compiler execution or new semantic evidence')


def main():
	p = argparse.ArgumentParser(); p.add_argument('archive', type=Path); p.add_argument('--output', type=Path); p.add_argument('--receipt', type=Path); a = p.parse_args(); result = verify(a.archive, a.output)
	if a.receipt: a.receipt.write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(result))


if __name__ == '__main__':
	main()
