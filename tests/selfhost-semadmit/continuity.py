#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the original OWNFlow expectations through the retained compatibility ABI."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tests/selfhost-ownflow'))
spec=importlib.util.spec_from_file_location('ownflow_original',ROOT/'tests/selfhost-ownflow/run.py')
original=importlib.util.module_from_spec(spec)
spec.loader.exec_module(original)


def main():
	p=argparse.ArgumentParser()
	for name in ('build','runtime','baseline'):
		p.add_argument('--'+name,type=Path,required=True)
	p.add_argument('--second-profile-build',type=Path)
	a=p.parse_args()
	a.runtime.mkdir(parents=True,exist_ok=False)
	rows=[]
	entries=json.loads((a.baseline/'frozen.json').read_text())
	assert len(entries)==93
	for item in entries:
		outputs=[]
		for mode in ('O0','O2'):
			product_dir=a.second_profile_build if mode=='O2' and a.second_profile_build else a.build
			argv=[str(product_dir/('astra-flow-'+mode)),'--compat',*item['paths']]
			start=time.monotonic()
			r=subprocess.run(argv,capture_output=True)
			name=item['name']+'-'+mode
			(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
			(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
			rows.append(dict(name=name,argv=argv,exit=r.returncode,seconds=time.monotonic()-start))
			(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
			o=original.decode(r.stdout)
			assert r.returncode==o['status']
			original.expectation(o,item)
			outputs.append(r.stdout)
		assert outputs[0]==outputs[1],item['name']
	print('PASS original OWNFlow 93, exact expectations and O0/O2 observations')


if __name__=='__main__':
	main()
