#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless numeric/token columns; archived values receive no semantic credit."""
from array import array
from pathlib import Path
import struct
import sys
import hashlib

# Reuse the independently restored R5 lossless token-column algorithm.
# Historical decoder SHA-256: 40fab4805fcf91924654b299ae758cf08aea7e4b6ac8b547af7f159af67da572
# Its installed/original file is read-only and unchanged.


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def little(values):
	if sys.byteorder != 'little': values.byteswap()
	return values.tobytes()


def encode(source, directory, logical, ordinal):
	groups = []; schemas = {}; dictionary = []; tokens = {}; order = array('I'); assert order.itemsize == 4
	def code(word, literal=False):
		if not literal and len(word) < 19:
			try:
				value = int(word)
				if -(1 << 60) < value < (1 << 60) and str(value).encode() == word: return value*2
			except ValueError: pass
		if word not in tokens: tokens[word] = len(dictionary); dictionary.append(word)
		return tokens[word]*2+1
	for line in source.open('rb'):
		words = line.split(); canonical = bool(words) and line == b' '.join(words)+b'\n'
		header = words[0] if canonical else b''; cells = words[1:] if canonical else [line]; key = (canonical, header, len(cells))
		if key not in schemas:
			schemas[key] = len(groups); groups.append(dict(header=header.hex(), raw=not canonical, columns=[array('q') for _ in cells], previous=[0]*len(cells), count=0))
		group_id = schemas[key]; group = groups[group_id]; order.append(group_id); group['count'] += 1
		for n, word in enumerate(cells):
			value = code(word, not canonical); group['columns'][n].append(value-group['previous'][n]); group['previous'][n] = value
	def part(name, raw):
		path = directory/(str(ordinal)+'.'+name); path.write_bytes(raw); return dict(path=path.name, sha256=sha(path), bytes=len(raw))
	parts = dict(order=part('order', little(order)), dictionary=part('dictionary', b''.join(struct.pack('<Q', len(word))+word for word in dictionary)))
	rows = []
	for g, group in enumerate(groups):
		rows.append(dict(header=group['header'], raw=group['raw'], count=group['count'], columns=[part(str(g)+'.'+str(n), little(column)) for n, column in enumerate(group['columns'])]))
	return dict(path=logical, bytes=source.stat().st_size, sha256=sha(source), mode=source.stat().st_mode & 0o777, lines=len(order), parts=parts, groups=rows)


def reconstruct(directory, row):
	def data(part):
		path = directory/part['path']; assert Path(part['path']).name == part['path'] and not path.is_symlink() and path.stat().st_size == part['bytes'] and sha(path) == part['sha256']; return path.read_bytes()
	def values(part, kind):
		result = array(kind); result.frombytes(data(part)); assert result.itemsize == (4 if kind == 'I' else 8)
		if sys.byteorder != 'little': result.byteswap()
		return result
	dictionary = []; raw = data(row['parts']['dictionary']); offset = 0
	while offset < len(raw):
		assert offset+8 <= len(raw); size = struct.unpack_from('<Q', raw, offset)[0]; offset += 8; assert offset+size <= len(raw); dictionary.append(raw[offset:offset+size]); offset += size
	order = values(row['parts']['order'], 'I'); assert len(order) == row['lines']; groups = []
	for group in row['groups']:
		columns = [values(part, 'q') for part in group['columns']]; assert all(len(column) == group['count'] for column in columns)
		groups.append(dict(columns=columns, previous=[0]*len(columns), position=0))
	for group_id in order:
		assert group_id < len(groups); group = groups[group_id]; schema = row['groups'][group_id]; position = group['position']; assert position < schema['count']; words = []
		for n, column in enumerate(group['columns']):
			group['previous'][n] += column[position]; code = group['previous'][n]
			if code % 2:
				assert 0 <= code//2 < len(dictionary); words.append(dictionary[code//2])
			else: words.append(str(code//2).encode())
		group['position'] += 1
		if schema['raw']:
			assert len(words) == 1; yield words[0]
		else: yield b' '.join([bytes.fromhex(schema['header']), *words])+b'\n'
	assert all(group['position'] == schema['count'] for group, schema in zip(groups, row['groups']))
