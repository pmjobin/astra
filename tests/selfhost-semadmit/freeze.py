#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Retain C0 stages and exact original FLOWSEM observations before edits."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
from corpus import cases


def main():
	p=argparse.ArgumentParser()
	p.add_argument('--compiler',type=Path,required=True)
	p.add_argument('--before',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	a=p.parse_args()
	a.runtime.mkdir(parents=True,exist_ok=False)
	entries=[]
	for item in cases():
		leaf=a.runtime/item['name']
		leaf.mkdir()
		path=Path(item.get('original_path',leaf/'input.astra'))
		if 'original_path' not in item:
			path.write_text(item['source']+'\n')
		item['paths']=[str(path)]
		item['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
		entries.append(item)
	(a.runtime/'frozen.json').write_text(json.dumps(entries,indent=2)+'\n')
	(a.runtime/'tools.json').write_text(json.dumps({str(x):hashlib.sha256(x.read_bytes()).hexdigest() for x in (a.compiler,a.before)},indent=2)+'\n')
	rows=[]
	for item in entries:
		for tool,stage in [(a.compiler,'--parse'),(a.compiler,'--check'),(a.compiler,'--tooling-index'),(a.before,'--flow')]:
			argv=[str(tool),stage,*item['paths']]
			start=time.monotonic()
			r=subprocess.run(argv,capture_output=True)
			name=('before' if tool==a.before else stage)
			leaf=a.runtime/item['name']
			(leaf/(name+'.stdout')).write_bytes(r.stdout)
			(leaf/(name+'.stderr')).write_bytes(r.stderr)
			rows.append(dict(argv=argv,exit=r.returncode,seconds=time.monotonic()-start))
			if stage=='--check':
				print(item['name'],r.returncode,r.stderr.decode().splitlines()[:2],flush=True)
	(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')


if __name__=='__main__':
	main()
