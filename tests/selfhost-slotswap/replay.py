#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay one exact predecessor gate with explicit writable-path routing."""
import argparse
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import time
import xml.etree.ElementTree as ET
from state import ROOT, RUNTIME, BUILD, PRIOR, read, sha


def main():
	resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); p.add_argument('--gate',required=True); p.add_argument('--command'); p.add_argument('--attempt',default='v1'); a = p.parse_args()
	assert a.gate.replace('-','').isalnum()
	assert a.attempt.replace('-','').isalnum()
	old = PRIOR/('final-v2-'+a.gate+'-'+a.mode); old_build = BUILD.parent/'genresource20'/old.name
	leaf = RUNTIME/('replay-'+a.gate+('-'+a.attempt if a.attempt != 'v1' else '')+'-'+a.mode); build = BUILD/leaf.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == expected for group in ('sources','tools') for path,expected in identity['identity'][group].items())
	commands = []; env = dict(os.environ,CCACHE_DISABLE='1'); env.pop('VALGRIND_OPTS',None); env.pop('LD_PRELOAD',None)
	for command in read(old/'commands.json'):
		if a.command and command['name'] != a.command: continue
		argv = command['argv'].copy()
		for i,word in enumerate(argv):
			if word.endswith('/astra-llvm-'+a.mode): word = str(a.component)
			if word.startswith(str(old_build)): word = str(build)+word[len(str(old_build)):]
			if word.startswith('--xml-file='+str(old)): word = word.replace(str(old),str(leaf),1)
			if i and argv[i-1] in ('--runtime','--output','--receipt') and word.startswith(str(old)): word = str(leaf)+word[len(str(old)):]
			argv[i] = word
		name = command['name']; start = time.monotonic()
		r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*argv],cwd=ROOT,capture_output=True,env=env,timeout=2400)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=argv,exit=r.returncode,expected=command['exit'],start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
		signal = -command['exit'] if command['exit'] < 0 and r.returncode == 128-command['exit'] and ('Command terminated by signal '+str(-command['exit'])) in (leaf/(name+'.time')).read_text() else None
		assert r.returncode == command['exit'] or signal == -command['exit'],(name,r.stderr.decode(errors='replace')[-1500:])
		if a.gate == 'own-faults':
			assert r.stdout == (old/(name+'.stdout')).read_bytes() and r.stderr == (old/(name+'.stderr')).read_bytes(),name
		if a.gate == 'own-lifetime' and name.endswith(('-execute','-memory')):
			def trace(data): return [line for line in data.splitlines() if re.fullmatch(r'(?:A|F) [0-9]+ [0-9]+|FAIL 36',line)]
			assert trace(r.stderr.decode()) == trace((old/(name+'.stderr')).read_text()),name
			if name.endswith('-memory') and 0 <= command['exit'] < 128:
				for word in argv:
					if word.startswith('--xml-file='): assert ET.parse(word.removeprefix('--xml-file=')).getroot().find('error') is None
		print(a.mode,a.gate,name,r.returncode,flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,gate=a.gate,component_sha256=sha(a.component),original_commands_sha256=sha(old/'commands.json'),commands=commands,recipe_sha256=sha(__file__)),indent=2)+'\n')


if __name__ == '__main__':
	main()
