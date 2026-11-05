#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the explicitly scoped remaining predecessor regression gates."""
import argparse
import json
from pathlib import Path
import subprocess
import sys
import time
from state import ROOT, RUNTIME, read, sha

GATES = [('inherited-text','inherited-text'),('inherited-indexpath','inherited-indexpath'),('own-new','new'),('own-family','family-repaired'),('own-twins','twins'),('own-extras','extras'),('own-mutations','mutations'),('own-faults','faults'),('own-lifetime','lifetime-repaired'),('resource','resource')]


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); a = p.parse_args()
	rows = []; output = RUNTIME/('suite-v2-'+a.mode+'.json'); assert not output.exists()
	for label,gate in GATES:
		argv = [sys.executable,'-B',ROOT/'tests/selfhost-genresource/replay.py','--component',a.component,'--mode',a.mode,'--gate',gate,'--name','final-v2-'+label+'-'+a.mode]
		recipe = sha(ROOT/'tests/selfhost-genresource/replay.py'); start = time.monotonic()
		r = subprocess.run(list(map(str,argv)),cwd=ROOT)
		assert recipe == sha(ROOT/'tests/selfhost-genresource/replay.py')
		rows.append(dict(gate=gate,label=label,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),routing_recipe_sha256=recipe))
		output.write_text(json.dumps(rows,indent=2)+'\n'); assert r.returncode == 0
		assert read(RUNTIME/('final-v2-'+label+'-'+a.mode)/'result.json')['status'] == 'PASS'


if __name__ == '__main__':
	main()
