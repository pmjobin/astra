#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe distinct concrete declaration counts under the unchanged 256 cap."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); a = p.parse_args()
	leaf = RUNTIME/('controls-v1-'+a.mode); leaf.mkdir(exist_ok=False); results = {}
	for name,expected in [('duplicate',1),('distinct',128),('exhaust',256)]:
		path = PRIOR/'controls-input-v1'/(name+'.astra'); original = read(PRIOR/'controls-input-v1/identities.json')[path.name]; assert sha(path) == original['sha256']
		argv = [a.component,'--classstorage-source-ledger',a.mode,BUILD/'unused',path]; start = time.monotonic()
		with (leaf/(name+'.stdout')).open('xb') as out,(leaf/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=ROOT,stdout=out,stderr=err,timeout=300)
		declarations = []; nodes = []; errors = []
		for line in (leaf/(name+'.stdout')).read_text().splitlines():
			words = line.split()
			if words[:1] == ['DECL']: declarations.append(words)
			if words[:1] == ['NODE']: nodes.append(int(words[1]))
			if words[:1] == ['CHECKED_ERROR']: errors.append(bytes.fromhex(words[4]).decode())
		original_nodes = max(nodes); concrete = [row for row in declarations if int(row[2]) == 1 and int(row[3]) > original_nodes]
		assert len(concrete) == expected,(name,len(concrete),errors)
		assert errors == (['generic instance resource limit'] if name == 'exhaust' else [])
		results[name] = dict(argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),source_sha256=sha(path),original_nodes=original_nodes,concrete_function_declarations=len(concrete),diagnostics=errors,stdout_sha256=sha(leaf/(name+'.stdout')),scope='Checked-source distinct declaration accounting; whole-source Flow/native admission is separate.')
		print(a.mode,name,len(concrete),errors,flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,component_sha256=sha(a.component),observations=results,recipe_sha256=sha(__file__)),indent=2)+'\n')


if __name__ == '__main__':
	main()
