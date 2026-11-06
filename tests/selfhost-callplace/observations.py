#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Losslessly column-pack native NODE observations; never manufacture new facts."""
from array import array
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time


def sha(path):
	with path.open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def encode(source, directory, logical, ordinal):
	columns = [array('i') for _ in range(9)]; previous = [0]*9
	assert columns[0].itemsize == 4
	paths = []; path_ids = {}; prefix = bytearray(); suffix = bytearray(); finished = False; count = 0
	for line in source.open('rb'):
		if line.startswith(b'NODE '):
			assert not finished
			words = line.split(); assert len(words) == 10
			assert line == b' '.join(words)+b'\n'
			path = words[7].decode('ascii')
			if path not in path_ids: path_ids[path] = len(paths); paths.append(path)
			values = [int(word) for word in words[1:7]]+[path_ids[path],int(words[8]),int(words[9])]
			assert all(str(value).encode() == word for value,word in zip(values[:6]+values[7:],words[1:7]+words[8:]))
			for i,value in enumerate(values): columns[i].append(value-previous[i]); previous[i] = value
			count += 1
		elif count:
			finished = True; suffix.extend(line)
		else: prefix.extend(line)
	assert count > 0
	parts = {}
	for name,data in [('prefix',prefix),('suffix',suffix)]:
		path = directory/(str(ordinal)+'.'+name); path.write_bytes(data); parts[name] = dict(path=path.name,sha256=sha(path))
	for i,column in enumerate(columns):
		if sys.byteorder != 'little': column.byteswap()
		path = directory/(str(ordinal)+'.column-'+str(i)); path.write_bytes(column.tobytes()); parts[str(i)] = dict(path=path.name,sha256=sha(path))
	return dict(path=logical,bytes=source.stat().st_size,sha256=sha(source),mode=source.stat().st_mode & 0o777,count=count,paths=paths,parts=parts)


def reconstruct(directory, row):
	for part in row['parts'].values(): assert sha(directory/part['path']) == part['sha256']
	yield (directory/row['parts']['prefix']['path']).read_bytes()
	columns = []
	for i in range(9):
		column = array('i'); column.frombytes((directory/row['parts'][str(i)]['path']).read_bytes())
		assert column.itemsize == 4 and len(column) == row['count']
		if sys.byteorder != 'little': column.byteswap()
		columns.append(column)
	values = [0]*9
	for n in range(row['count']):
		for i in range(9): values[i] += columns[i][n]
		a,b,c,d,e,f,p,g,h = values
		yield ('NODE '+str(a)+' '+str(b)+' '+str(c)+' '+str(d)+' '+str(e)+' '+str(f)+' '+row['paths'][p]+' '+str(g)+' '+str(h)+'\n').encode('ascii')
	yield (directory/row['parts']['suffix']['path']).read_bytes()


def main():
	p = argparse.ArgumentParser(); p.add_argument('root',type=Path); p.add_argument('--plan',type=Path); p.add_argument('--verify-only',action='store_true'); p.add_argument('--receipt',type=Path); a = p.parse_args()
	root = a.root.resolve(); plan = a.plan or root/'derived-observations/restore-plan.json'; model = json.loads(plan.read_text()); assert model['format'] == 'astra-lossless-native-observations/1'; results = []; started = time.monotonic()
	for row in model['files']:
		target = root/row['path']; assert target.resolve().is_relative_to(root) and not target.is_symlink()
		writer = None
		if not a.verify_only:
			assert not target.exists(); target.parent.mkdir(parents=True,exist_ok=True); writer = target.open('xb')
		observed = hashlib.sha256(); size = 0
		try:
			for data in reconstruct(plan.parent,row):
				observed.update(data); size += len(data)
				if writer: writer.write(data)
		finally:
			if writer: writer.close(); target.chmod(row['mode'])
		assert observed.hexdigest() == row['sha256'] and size == row['bytes'],row['path']
		results.append(dict(path=row['path'],bytes=size,sha256=observed.hexdigest(),nodes=row['count'])); print(row['path'],'BYTE_EXACT',flush=True)
	result = dict(status='PASS',files=results,final_commit=model['final_commit'],final_tree=model['final_tree'],seconds=time.monotonic()-started,plan_sha256=sha(plan),recipe_sha256=sha(Path(__file__)),classification='Lossless byte reconstruction of recorded executions, not compiler execution or new semantic proof.')
	if a.receipt: a.receipt.write_text(json.dumps(result,indent=2)+'\n')
	print('All',len(results),'native observations reconstruct byte-exactly',flush=True)


if __name__ == '__main__':
	main()
