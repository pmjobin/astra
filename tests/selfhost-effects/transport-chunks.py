#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless content chunks; decode to a standard archive for the unchanged verifier."""
import argparse
from array import array
import hashlib
import io
import json
import lzma
import mmap
from pathlib import Path
import re
import struct
import subprocess
import sys
import tarfile
import zlib

CHUNK_BOUNDARY_SOURCE = r'''// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

int main(void) {
	uint64_t gear[256], seed = UINT64_C(0x9e3779b97f4a7c15);
	for (int i = 0; i < 256; i++) {
		seed ^= seed >> 12;
		seed ^= seed << 25;
		seed ^= seed >> 27;
		gear[i] = seed * UINT64_C(2685821657736338717);
	}
	char *line = NULL;
	size_t capacity = 0;
	while (getline(&line, &capacity, stdin) >= 0) {
		line[strcspn(line, "\n")] = 0;
		FILE *input = fopen(line, "rb");
		struct stat info;
		if (!input || fstat(fileno(input), &info)) return 2;
		size_t size = (size_t)info.st_size;
		unsigned char *data = size ? mmap(NULL, size, PROT_READ, MAP_PRIVATE, fileno(input), 0) : NULL;
		if (size && data == MAP_FAILED) return 3;
		printf("%zu", size);
		uint64_t hash = 0;
		size_t first = 0;
		for (size_t i = 0; i < size; i++) {
			hash = (hash << 1) + gear[data[i]];
			size_t count = i + 1 - first;
			if (count >= 1024 && (!(hash & 2047) || count >= 16384)) {
				printf(" %zu", i + 1);
				first = i + 1;
				hash = 0;
			}
		}
		if (first < size) printf(" %zu", size);
		putchar('\n');
		if (size) munmap(data, size);
		fclose(input);
	}
	free(line);
	return ferror(stdin) || ferror(stdout);
}
'''


def digest(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def digit_columns(source, directory, logical):
	"""Exact byte tokens in the existing independent raw-column wire format."""
	key = digest(source); directory.mkdir(exist_ok=True)
	dictionary, tokens = [], {}
	order, columns, previous = array('I'), [array('q') for _ in range(513)], [0]*513
	prior_context = 0
	for match in re.finditer(rb'[0-9]+|[^0-9]+', source.read_bytes()):
		word = match.group(); number = int(word) if 48 <= word[0] <= 57 and len(word) < 19 else None
		if number is not None and number < (1 << 60) and str(number).encode() == word:
			group, code = 1+prior_context+64*(min(len(word), 8)-1), number*2
		else:
			if word not in tokens: tokens[word] = len(dictionary); dictionary.append(word)
			prior_context = zlib.crc32(word[-16:]) & 63; group, code = 0, tokens[word]*2+1
		columns[group].append(code-previous[group]); previous[group] = code; order.append(group)
	def part(name, data):
		path = directory/(key[:20]+'.digits.'+name); path.write_bytes(data)
		return dict(path=path.name, sha256=digest(path), bytes=len(data))
	def little(values):
		if sys.byteorder != 'little': values.byteswap()
		return values.tobytes()
	assert order.itemsize == 4 and all(column.itemsize == 8 for column in columns)
	parts = dict(order=part('order', little(order)), dictionary=part('dictionary', b''.join(struct.pack('<Q', len(word))+word for word in dictionary)))
	groups = [dict(header='', raw=True, count=len(column), columns=[part(str(ordinal), little(column))]) for ordinal, column in enumerate(columns)]
	return dict(path=logical, bytes=source.stat().st_size, sha256=key, mode=source.stat().st_mode & 0o777, lines=len(order), parts=parts, groups=groups, byte_token_encoding='Decimal byte runs and exact literal runs; raw column units concatenate without interpretation or newline changes.')


def encode(pending, leaf, build):
	build.mkdir(exist_ok=True); source = build/'transport-chunks.c'; source.write_text(CHUNK_BOUNDARY_SOURCE); product = build/'transport-chunks'
	argv = ['cc', '-O2', '-Wall', '-Wextra', '-Werror', source, '-o', product]
	r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/'chunk-build.time', *map(str, argv)], capture_output=True)
	(leaf/'chunk-build.stdout').write_bytes(r.stdout); (leaf/'chunk-build.stderr').write_bytes(r.stderr); assert r.returncode == 0, r.stderr
	names = sorted(name for name in pending if name != 'INDEX.json')
	inventory = ''.join(str(pending[name])+'\n' for name in names).encode()
	r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/'chunk-boundaries.time', product], input=inventory, capture_output=True)
	(leaf/'chunk-boundaries.stdout').write_bytes(r.stdout); (leaf/'chunk-boundaries.stderr').write_bytes(r.stderr); assert r.returncode == 0, r.stderr
	rows = r.stdout.decode().splitlines(); assert len(rows) == len(names)
	pool = leaf/'content-chunk-pool.bin'; table, blobs, seen = [], {}, {}
	with pool.open('w+b') as out:
		for name, row in zip(names, rows, strict=True):
			values = list(map(int, row.split())); size, cuts = values[0], values[1:]; path = pending[name]
			assert path.stat().st_size == size and (cuts[-1] == size if size else not cuts)
			first, parts, actual = 0, [], hashlib.sha256()
			with path.open('rb') as stream:
				for last in cuts:
					assert first < last <= size
					data = stream.read(last-first); assert len(data) == last-first
					actual.update(data); key = hashlib.sha256(data).digest()
					if key not in seen:
						seen[key] = len(table); out.seek(0, 2); offset = out.tell(); out.write(data); table.append([offset, len(data)])
					ordinal = seen[key]; offset, count = table[ordinal]
					out.seek(offset); assert count == len(data) and out.read(count) == data
					parts.append(ordinal); first = last
			assert name == 'blobs/'+actual.hexdigest()
			blobs[name] = dict(bytes=size, parts=parts)
			# Sorting distinct chunks by their actual bytes places similar captures
			# together without using a filename, source meaning or claimed verdict.
	with pool.open('rb') as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as mapped:
		ordered = sorted(((ordinal, mapped[offset:offset+count]) for ordinal, (offset, count) in enumerate(table)), key=lambda row: row[1])
	new_pool = leaf/'sorted-content-chunk-pool.bin'; remap, sorted_table = {}, []
	with new_pool.open('xb') as out:
		for ordinal, data in ordered:
			remap[ordinal] = len(sorted_table); sorted_table.append([out.tell(), len(data)]); out.write(data)
	for row in blobs.values(): row['parts'] = [remap[ordinal] for ordinal in row['parts']]
	pool, table = new_pool, sorted_table
	storage = dict(format='astra-content-chunks/1', pool_blob='blobs/'+digest(pool), pool_bytes=pool.stat().st_size, chunks=table, blobs=blobs)
	receipt = dict(source_sha256=digest(source), recipe_sha256=digest(__file__), product_sha256=digest(product), build_argv=list(map(str, argv)), boundaries_sha256=hashlib.sha256(r.stdout).hexdigest(), original_blob_bytes=sum(row['bytes'] for row in blobs.values()), unique_chunk_bytes=pool.stat().st_size, original_blobs=len(blobs), unique_chunks=len(table), target_execution_credit=0, limitation='Content-defined chunks reconstruct exact original blob bytes. No source, proof result, command receipt or original logical file is removed or interpreted. The standalone standard-library decoder hashes every reconstructed blob before the unchanged independent original logical-file decoder runs.')
	(leaf/'chunk-codec-receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
	return pool, storage, receipt


def decode(archive, output, expected=None):
	assert not output.exists(); temporary = output.with_suffix('.pool'); assert not temporary.exists()
	observed = {}
	with tarfile.open(archive, 'r|xz') as packed:
		for member in packed:
			assert member.isfile() and member.name not in observed
			stream = packed.extractfile(member)
			if member.name == 'INDEX.json': index = json.load(stream); observed[member.name] = None; continue
			assert member.name.startswith('blobs/') and len(Path(member.name).parts) == 2 and not temporary.exists()
			actual = hashlib.sha256()
			with temporary.open('xb') as out:
				for block in iter(lambda: stream.read(1048576), b''): out.write(block); actual.update(block)
			assert member.name == 'blobs/'+actual.hexdigest(); observed[member.name] = temporary.stat().st_size
	assert index['format'] == 'astra-effects25-evidence/4' and index['milestone'] == 'ASTRA-SELFHOST-EFFECTS-25-R5'
	if expected is not None: assert index == expected
	storage = index['storage']; assert storage['format'] == 'astra-content-chunks/1' and observed == {'INDEX.json': None, storage['pool_blob']: storage['pool_bytes']}
	assert {row['blob'] for row in index['files'].values() if 'blob' in row} == set(storage['blobs'])
	end = 0
	for offset, size in storage['chunks']: assert offset == end and size > 0; end += size
	assert end == storage['pool_bytes']
	standard = dict(index); standard['format'] = 'astra-effects25-evidence/3'; standard.pop('storage')
	with temporary.open('rb') as source, mmap.mmap(source.fileno(), 0, access=mmap.ACCESS_READ) as pool, lzma.LZMAFile(output, 'wb', preset=0) as compressed, tarfile.open(fileobj=compressed, mode='w|') as packed:
		for name, row in storage['blobs'].items():
			data = bytearray()
			for ordinal in row['parts']:
				assert 0 <= ordinal < len(storage['chunks']); offset, size = storage['chunks'][ordinal]; data.extend(pool[offset:offset+size])
			assert len(data) == row['bytes'] and name == 'blobs/'+hashlib.sha256(data).hexdigest()
			entry = tarfile.TarInfo(name); entry.mode = 0o644; entry.size = len(data); packed.addfile(entry, io.BytesIO(data))
		data = (json.dumps(standard, indent=2)+'\n').encode(); entry = tarfile.TarInfo('INDEX.json'); entry.mode = 0o644; entry.size = len(data); packed.addfile(entry, io.BytesIO(data))
	return index


def self_test(root, build):
	root.mkdir(); fixtures = [b'', bytes(range(256)), b'prefix'+bytes(range(256))*500, b'changed-prefix'+bytes(range(256))*500, b'\0'*70000, b'\xff'*65537]
	pending, files = {}, {}
	for ordinal, data in enumerate(fixtures):
		hash_value = hashlib.sha256(data).hexdigest(); path = root/hash_value; path.write_bytes(data); pending['blobs/'+hash_value] = path
		files['fixture/'+str(ordinal)] = dict(blob='blobs/'+hash_value, sha256=hash_value, bytes=len(data), mode='0o644')
	pool, storage, receipt = encode(pending, root, build)
	index = dict(format='astra-effects25-evidence/4', milestone='ASTRA-SELFHOST-EFFECTS-25-R5', files=files, storage=storage)
	def archive(name, data, model):
		path = root/(name+'.tar.xz')
		with tarfile.open(path, 'w:xz') as packed:
			for key, value in [(model['storage']['pool_blob'], data), ('INDEX.json', (json.dumps(model)+'\n').encode())]:
				entry = tarfile.TarInfo(key); entry.size = len(value); packed.addfile(entry, io.BytesIO(value))
		return path
	raw = pool.read_bytes(); original = archive('valid', raw, index); output = root/'valid-standard.tar.xz'; assert decode(original, output, index) == index
	with tarfile.open(output, 'r:xz') as packed:
		for ordinal, data in enumerate(fixtures): assert packed.extractfile(files['fixture/'+str(ordinal)]['blob']).read() == data
	controls = []
	for category in ['altered-byte', 'invalid-chunk-id', 'incomplete-pool']:
		model = json.loads(json.dumps(index)); data = raw
		if category == 'altered-byte': data = bytes([raw[0]^1])+raw[1:]; model['storage']['pool_blob'] = 'blobs/'+hashlib.sha256(data).hexdigest()
		elif category == 'invalid-chunk-id': next(row for row in model['storage']['blobs'].values() if row['parts'])['parts'][0] = len(storage['chunks'])
		else: model['storage']['chunks'][-1][1] -= 1
		path = archive(category, data, model)
		try: decode(path, root/(category+'-standard.tar.xz'))
		except AssertionError: controls.append(category)
		else: raise AssertionError(category+' accepted')
	result = dict(status='EXACT_CONTENT_CHUNKS_AND_CORRUPTION_CONTROLS', recipe_sha256=digest(__file__), fixtures=len(fixtures), rejected=controls, original_blob_bytes=receipt['original_blob_bytes'], unique_chunk_bytes=receipt['unique_chunk_bytes'], Astra_execution_credit=0)
	(root/'result.json').write_text(json.dumps(result, indent=2)+'\n'); print(json.dumps(result))


def main():
	p = argparse.ArgumentParser(); p.add_argument('archive', nargs='?', type=Path); p.add_argument('--output', type=Path, required=True); p.add_argument('--self-test', action='store_true'); p.add_argument('--build', type=Path); a = p.parse_args()
	if a.self_test:
		assert a.archive is None and a.build is not None
		self_test(a.output, a.build)
		return
	assert a.archive is not None
	index = decode(a.archive, a.output)
	print(json.dumps(dict(status='EXACT_BLOBS_RECONSTRUCTED', logical_files=len(index['files']), original_blobs=len(index['storage']['blobs']), standard_archive_sha256=digest(a.output), classification='Lossless evidence decoding only; no semantic or target execution credit.')))


if __name__ == '__main__':
	main()
