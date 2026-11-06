#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless token columns for raw reference observations; no semantic inference."""
from array import array
import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys
import time


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


def main():
	p = argparse.ArgumentParser(); p.add_argument('root', type=Path); p.add_argument('--plan', type=Path); p.add_argument('--verify-only', action='store_true'); p.add_argument('--receipt', type=Path); a = p.parse_args()
	root = a.root.resolve(); plan = a.plan or root/'derived-columns/restore-plan.json'; model = json.loads(plan.read_text()); assert model['format'] == 'astra-lossless-token-columns/1'; started = time.monotonic(); results = []
	for row in model['files']:
		target = root/row['path']; assert target.resolve().is_relative_to(root) and not target.is_symlink(); writer = None
		if not a.verify_only:
			assert not target.exists(); target.parent.mkdir(parents=True, exist_ok=True); writer = target.open('xb')
		observed = hashlib.sha256(); size = 0
		try:
			for raw in reconstruct(plan.parent, row):
				observed.update(raw); size += len(raw)
				if writer: writer.write(raw)
		finally:
			if writer: writer.close(); target.chmod(row['mode'])
		assert size == row['bytes'] and observed.hexdigest() == row['sha256'], row['path']; results.append(dict(path=row['path'], bytes=size, sha256=observed.hexdigest(), lines=row['lines'])); print(row['path'], 'BYTE_EXACT', flush=True)
	result = dict(status='PASS', files=results, seconds=time.monotonic()-started, final_commit=model['final_commit'], final_tree=model['final_tree'], plan_sha256=sha(plan), recipe_sha256=sha(__file__), classification='Lossless recorded byte reconstruction; not a new execution or semantic proof.')
	if a.receipt: a.receipt.write_text(json.dumps(result, indent=2)+'\n')


if __name__ == '__main__':
	main()
