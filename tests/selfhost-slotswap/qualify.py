#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute the new programs, complete stage checks and record controls."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, RUNTIME, BUILD, C0, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); p.add_argument('--finish',action='store_true'); a = p.parse_args()
	leaf = RUNTIME/('qualified-v1-'+a.mode); build = BUILD/leaf.name
	if not a.finish: leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	selection = RUNTIME/'corpus-v3/selection.json'; commands = read(leaf/'commands.json') if a.finish else []; env = dict(os.environ,CCACHE_DISABLE='1'); env.pop('VALGRIND_OPTS',None); env.pop('LD_PRELOAD',None)
	def run(argv,name,expected=0):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=ROOT,capture_output=True,env=env,timeout=2400)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
		print(a.mode,name,r.returncode,flush=True); assert r.returncode == expected,r.stderr.decode(errors='replace')[-2000:]
	if not a.finish: run([sys.executable,'-B',ROOT/'tests/selfhost-classstorage/run.py','--compiler',C0,'--compiler-sha256',sha(C0),'--component',a.component,'--mode',a.mode,'--selection',selection,'--build',build/'products','--runtime',leaf/'observations'],'native')
	rows = read(leaf/'observations/results.json'); assert len(rows) == 13 and all(row['baseline_complete'] for row in rows)
	for row in ([] if a.finish else read(selection)):
		for stage in ('core','cfg'): run([a.component,'--classstorage-'+stage,a.mode,build/'unused',*[s['path'] for s in row['sources']]],row['name']+'-'+stage)
	row = next(row for row in read(selection) if row['name'] == 'nested-field-local'); output = build/'preserved.o'
	if not a.finish: run([a.component,'--classstorage-emit-obj',a.mode,output,*[s['path'] for s in row['sources']]],'valid-model-twin')
	original = sha(output)
	if not a.finish: run([a.component,'--classstorage-slotswap-mutations',a.mode,output,*[s['path'] for s in row['sources']]],'record-models')
	assert (leaf/'record-models.stdout').read_text().count('SLOTSWAP_RECORD_MUTATION ') == 14 and sha(output) == original
	if not a.finish:
		run([sys.executable,'-B',ROOT/'tests/selfhost-slotswap/physical.py','--qualification',leaf/'observations','--mode',a.mode],'physical')
		run([sys.executable,'-B',ROOT/'tests/selfhost-slotswap/lifetime.py','--qualification',leaf/'observations','--mode',a.mode],'lifetime')
	for current in rows:
		assert all(sha(s['path']) == s['sha256'] for s in current['sources']) and all(sha(p['path']) == p['sha256'] for p in current['products'].values())
	assert read(RUNTIME/('physical-v1-'+a.mode)/'result.json')['status'] == read(RUNTIME/('lifetime-v1-'+a.mode)/'result.json')['status'] == 'PASS'
	run([sys.executable,'-B',ROOT/'tests/selfhost-slotswap/negative.py','--component',a.component,'--mode',a.mode],'source-controls-v2')
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,component_sha256=sha(a.component),new_source_programs=13,record_authority_mutations=14,external_LLVM_valid_physical_alternatives=6,programs=rows,commands=commands,recipe_sha256=sha(__file__)),indent=2)+'\n')


if __name__ == '__main__':
	main()
