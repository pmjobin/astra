#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Retain actual checked/Flow diagnostics behind each source refusal."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); a = p.parse_args()
	leaf = RUNTIME/('negative-observation-v1-'+a.mode); leaf.mkdir(exist_ok=False); previous = RUNTIME/('negative-v2-'+a.mode); result = read(previous/'result.json'); rows = []
	assert result['status'] == 'PASS' and result['component_sha256'] == sha(a.component)
	for row in result['mutations']:
		name = row['category']; source = previous/(name+'.astra'); assert sha(source) == row['source_sha256']
		argv = [a.component,'--classstorage-admit',a.mode,BUILD/'unused',source]; start = time.monotonic()
		r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=ROOT,capture_output=True,timeout=180)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		lines = r.stdout.decode().splitlines(); assert r.returncode in (1,3,4) and 'STATUS 0 0' not in lines,(name,r.returncode)
		diagnostics = []
		for line in lines:
			words = line.split()
			if words[:1] == ['CHECKED_ERROR']: diagnostics.append(dict(stage='Checked',path=bytes.fromhex(words[1]).decode(),span=list(map(int,words[2:4])),message=bytes.fromhex(words[4]).decode()))
			if words[:1] in (['STATUS'],['G'],['DEFER']): diagnostics.append(line)
		rows.append(dict(category=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),diagnostics=diagnostics,stdout_sha256=sha(leaf/(name+'.stdout')),classification='Actual first denying authority retained; earlier domain/escape refusals do not establish a later swap/loan check'))
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,component_sha256=sha(a.component),observations=rows,recipe_sha256=sha(__file__)),indent=2)+'\n'); print(a.mode,len(rows),'actual checked/Flow source refusals retained')


if __name__ == '__main__':
	main()
