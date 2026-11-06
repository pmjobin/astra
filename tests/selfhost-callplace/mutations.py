#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Require 28 actual generic/Core/CFG/SSA consumer denials at each profile."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); a = p.parse_args()
	leaf = RUNTIME/('models-'+a.mode); build = BUILD/leaf.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	case = next(row for row in read(RUNTIME/'corpus-v6/selection.json') if row['name'] == 'multiple-arguments-order')
	assert all(sha(s['path']) == s['sha256'] for s in case['sources'])
	output = build/'preserved.o'; output.write_bytes(b'preserved model-test destination\n'); before = sha(output)
	argv = [a.component,'--classstorage-callplace-mutations',a.mode,output,*[s['path'] for s in case['sources']]]
	env = dict(os.environ,CCACHE_DISABLE='1'); env.pop('LD_PRELOAD',None); env.pop('VALGRIND_OPTS',None)
	start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/'models.time',*map(str,argv)],cwd=ROOT,capture_output=True,env=env,timeout=180)
	(leaf/'models.stdout').write_bytes(r.stdout); (leaf/'models.stderr').write_bytes(r.stderr)
	command = dict(argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic()); (leaf/'commands.json').write_text(json.dumps([command],indent=2)+'\n')
	assert r.returncode == 0,r.stderr.decode()
	rows = [line.split() for line in r.stdout.decode().splitlines() if line.startswith('CALLPLACE_MODEL_MUTATION ')]
	assert len(rows) == 28 and {int(row[1]) for row in rows} == set(range(28))
	assert all(len(row) == 4 and int(row[2]) > 0 and int(row[2]) != 2 and row[3] == 'VALID_RESTORED' for row in rows)
	assert sha(output) == before
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,component_sha256=sha(a.component),source=case['sources'],mutations=[dict(category=int(row[1]),stage=int(row[2]),consumer='Generic' if int(row[1]) < 11 or int(row[1]) == 23 else 'Core' if int(row[1]) < 24 else 'CFG' if int(row[1]) < 26 else 'SSA') for row in rows],commands=[command],preserved_destination_sha256=before,limitation='Real model-consumer tests; source negatives and post-emission physical alternatives have separate ledgers.'),indent=2)+'\n')
	print(a.mode,'28 model mutations rejected; exact valid twins restored')


if __name__ == '__main__':
	main()
