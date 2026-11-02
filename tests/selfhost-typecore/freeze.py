#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze authored expectations, then execute the independent C0 baseline."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time
from corpus import cases, materialize


def main():
	p=argparse.ArgumentParser()
	p.add_argument('--compiler',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	a=p.parse_args()
	a.runtime.mkdir(parents=True,exist_ok=False)
	entries=[]
	for item in cases():
		leaf=a.runtime/item['name'];leaf.mkdir()
		files,marks=materialize(item['files'])
		paths={name:str(leaf/name) for name in files}
		for name,data in files.items(): (leaf/name).write_bytes(data)
		entries.append(dict(item,paths=list(paths.values()),marks={tag:(paths[name],start,end) for tag,(name,start,end) in marks.items()},sha256={paths[name]:hashlib.sha256(data).hexdigest() for name,data in files.items()}))
	(a.runtime/'frozen.json').write_text(json.dumps(entries,indent=2)+'\n')
	rows=[]
	for item in entries:
		for mode in ('--dump-semantics','--tooling-index','--check'):
			start=time.monotonic()
			r=subprocess.run(['/usr/bin/time','-v',a.compiler,mode,*item['paths']],capture_output=True)
			name=item['name']+mode
			(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
			(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
			rows.append(dict(name=name,argv=[str(a.compiler),mode,*item['paths']],exit=r.returncode,seconds=time.monotonic()-start))
		print(item['name'],rows[-3]['exit'],rows[-2]['exit'],rows[-1]['exit'],flush=True)
	(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
	(a.runtime/'compiler.json').write_text(json.dumps(dict(path=str(a.compiler),sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest()),indent=2)+'\n')


if __name__=='__main__': main()
