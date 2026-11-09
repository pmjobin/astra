#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bounded u8 index parts: each index maps to its identical byte value."""
import argparse
import hashlib
import json
from pathlib import Path


def digest(data): return hashlib.sha256(data).hexdigest()


def encode(source, output, stem):
	output.mkdir(); data = source.read_bytes()
	model = dict(format='astra-indexed-bytes/1', element_type='u8', mapping='identity: index 0..255 maps to the same byte', source_name=source.name, raw_bytes=len(data), raw_sha256=digest(data), parts=[])
	for first in range(0, len(data), 1800000):
		part = data[first:first+1800000]; name = stem+'-part-'+str(first//1800000+1).zfill(3)+'.indices'; (output/name).write_bytes(part)
		model['parts'].append(dict(name=name, bytes=len(part), sha256=digest(part)))
	index = output/(stem+'-encoding.json'); index.write_text(json.dumps(model, indent=2)+'\n')
	assert decode(index) == (model, data)
	return index


def decode(index):
	model = json.loads(index.read_text()); assert model['format'] == 'astra-indexed-bytes/1' and model['element_type'] == 'u8' and model['mapping'] == 'identity: index 0..255 maps to the same byte'
	parts = []
	for row in model['parts']:
		assert Path(row['name']).name == row['name'] and row['name'].endswith('.indices')
		path = index.parent/row['name']; assert not path.is_symlink(); data = path.read_bytes()
		assert len(data) == row['bytes'] <= 1800000 and digest(data) == row['sha256']; parts.append(data)
	data = b''.join(parts); assert len(data) == model['raw_bytes'] and digest(data) == model['raw_sha256']
	return model, data


def main():
	p = argparse.ArgumentParser(); p.add_argument('index', type=Path); p.add_argument('--output', type=Path, required=True); a = p.parse_args(); model, data = decode(a.index)
	assert not a.output.exists(); a.output.write_bytes(data); print(json.dumps(dict(status='BYTE_EXACT', bytes=len(data), sha256=model['raw_sha256'], Astra_execution_credit=0)))


if __name__ == '__main__':
	main()
