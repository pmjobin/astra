#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the independent source, ABI, LLVM, ELF and unsuppressed memory checks."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, RUNTIME, BUILD, C0, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); p.add_argument('--version',default='v1'); a = p.parse_args()
	leaf = RUNTIME/('qualified-'+a.version+'-'+a.mode); build = BUILD/leaf.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	selection = RUNTIME/'corpus-v4/selection.json'; commands = []
	def run(argv,name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=ROOT,capture_output=True,timeout=2400)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
		print(a.mode,name,r.returncode,flush=True); assert r.returncode == 0,r.stderr.decode(errors='replace')[-2000:]
	run([sys.executable,'-B',ROOT/'tests/selfhost-classstorage/run.py','--compiler',C0,'--compiler-sha256',sha(C0),'--component',a.component,'--mode',a.mode,'--selection',selection,'--build',build/'products','--runtime',leaf/'observations'],'native')
	rows = read(leaf/'observations/results.json'); assert len(rows) == 15 and all(row['baseline_complete'] for row in rows)
	for row in read(selection):
		for stage in ('core','cfg','generic-plan'):
			run([a.component,'--classstorage-'+stage,a.mode,build/'unused',*[s['path'] for s in row['sources']]],row['name']+'-'+stage)
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,component_sha256=sha(a.component),new_source_programs=15,programs=rows,commands=commands,recipe_sha256=sha(__file__)),indent=2)+'\n')


if __name__ == '__main__':
	main()
