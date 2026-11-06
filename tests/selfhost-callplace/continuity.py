#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay exact source-status and module-layout lifetime controls."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--O0',type=Path,required=True); p.add_argument('--O2',type=Path,required=True); a = p.parse_args()
	leaf = RUNTIME/'continuity'; leaf.mkdir(exist_ok=False); commands = []; results = {}
	for mode in ('O0','O2'):
		results[mode] = {}
		for label,gate in [('source-status','inherited-native'),('layout-lifetime','inherited-native-layout')]:
			old = PRIOR/('replay-'+gate+'-'+mode); command = read(old/'commands.json')[0]; argv = command['argv'].copy(); argv[argv.index('--component')+1] = str(getattr(a,mode)); name = label+'-'+mode
			for flag,value in [('--build',BUILD/name),('--runtime',leaf/name)]: argv[argv.index(flag)+1] = str(value)
			start = time.monotonic()
			r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*argv],cwd=ROOT,capture_output=True,timeout=300)
			(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
			commands.append(dict(name=name,argv=argv,exit=r.returncode,start=start,end=time.monotonic(),prior_command_sha256=sha(old/'commands.json'))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
			assert r.returncode == 0,r.stderr.decode()[-2000:]
			receipt = read(leaf/name/'result.json'); assert receipt['status'] == 'PASS'
			if label == 'source-status':
				observed = read(leaf/name/'observations/result.json')['outcomes']; assert observed == {'0':56,'4':12,'3':12}
				results[mode][label] = observed
			else: results[mode][label] = receipt
			print(name,'PASS',flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='INHERITED_CONTROLS_PASS',results=results,commands=commands,recipe_sha256=sha(__file__)),indent=2)+'\n')


if __name__ == '__main__':
	main()
