#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Preserve large raw evidence as bounded, hashed gzip/base64 text parts."""
from pathlib import Path
import argparse
import base64
import gzip
import hashlib
import json
import re

LIMIT = 1800000


def sha(data): return hashlib.sha256(data).hexdigest()


def decode(index):
	index = index.resolve(strict=True); model = json.loads(index.read_text())
	assert model['format'] == 'astra-encoded-evidence/1' and model['codec'] == 'gzip+base64'
	parts = []
	for row in model['parts']:
		assert Path(row['name']).name == row['name'] and row['name'].endswith('.txt')
		part = index.parent / row['name']; assert not part.is_symlink()
		data = part.read_bytes(); assert len(data) == row['bytes'] <= LIMIT and sha(data) == row['sha256']
		parts.append(data)
	encoded = b''.join(parts); assert len(encoded) == model['encoded_bytes'] and sha(encoded) == model['encoded_sha256']
	packed = base64.b64decode(encoded, validate=True); assert len(packed) == model['packed_bytes'] and sha(packed) == model['packed_sha256']
	raw = gzip.decompress(packed); assert len(raw) == model['raw_bytes'] and sha(raw) == model['raw_sha256']
	return model, raw


def main():
	p = argparse.ArgumentParser(description=__doc__); commands = p.add_subparsers(dest='mode', required=True)
	pack = commands.add_parser('pack'); pack.add_argument('--input', type=Path, required=True); pack.add_argument('--output', type=Path, required=True); pack.add_argument('--stem', required=True)
	check = commands.add_parser('verify'); check.add_argument('index', type=Path)
	unpack = commands.add_parser('unpack'); unpack.add_argument('index', type=Path); unpack.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	if a.mode in ['verify', 'unpack']:
		model, raw = decode(a.index)
		if a.mode == 'unpack':
			assert not a.output.is_symlink()
			if a.output.exists(): assert a.output.read_bytes() == raw
			else: a.output.write_bytes(raw)
		print(json.dumps(dict(status='PASS', raw_bytes=model['raw_bytes'], raw_sha256=model['raw_sha256']))); return
	assert re.fullmatch('[a-z0-9][a-z0-9-]*', a.stem)
	assert a.input.is_file() and not a.input.is_symlink()
	source = a.input.resolve(strict=True); output = a.output.resolve(); output.mkdir(parents=True, exist_ok=True)
	raw = source.read_bytes(); assert len(raw) <= 1024**3
	packed = gzip.compress(raw, compresslevel=9, mtime=0); encoded = base64.b64encode(packed)
	model = dict(format='astra-encoded-evidence/1', codec='gzip+base64', source_name=source.name, raw_bytes=len(raw), raw_sha256=sha(raw), packed_bytes=len(packed), packed_sha256=sha(packed), encoded_bytes=len(encoded), encoded_sha256=sha(encoded), parts=[])
	for offset in range(0, len(encoded), LIMIT):
		data = encoded[offset:offset+LIMIT]; name = a.stem + '-part-' + str(offset//LIMIT+1).zfill(3) + '.txt'; path = output / name
		assert not path.is_symlink()
		if path.exists(): assert path.read_bytes() == data
		else: path.write_bytes(data)
		model['parts'].append(dict(name=name, bytes=len(data), sha256=sha(data)))
	index = output / (a.stem + '-encoding.json'); data = (json.dumps(model, indent=2)+'\n').encode()
	if index.exists(): assert index.read_bytes() == data
	else: index.write_bytes(data)
	assert decode(index) == (model, raw)
	print(json.dumps(dict(status='PASS', index=str(index), raw_bytes=len(raw), encoded_bytes=len(encoded), parts=len(model['parts']), raw_sha256=sha(raw))))


if __name__ == '__main__': main()
