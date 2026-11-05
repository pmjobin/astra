#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Diagnostic only: exercise a completed product with an incomplete build receipt."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--name', required=True); p.add_argument('--mode', choices=('O0','O2'), required=True); a = p.parse_args()
	leaf = RUNTIME/a.name; leaf.mkdir(exist_ok=False); build = BUILD/a.name; build.mkdir(exist_ok=False); commands = []
	for row in read(RUNTIME/'corpus-v1/selection.json'):
		sources = [source['path'] for source in row['sources']]; ready = True
		for stage in ('core','cfg','ssa','emit-obj','link','execute'):
			output = build/(row['name']+'.o'); app = build/row['name']; expected = 0
			if stage == 'link': argv = ['gcc', output, '-o', app]
			elif stage == 'execute': argv = [app]; expected = row['expected_exit']
			else: argv = [a.component, '--classstorage-'+stage, a.mode, output, *sources]
			label = row['name']+'-'+stage; start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(label+'.time'),*map(str,argv)], cwd=ROOT, capture_output=True, env=dict(os.environ,CCACHE_DISABLE='1'), timeout=180)
			(leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=label,argv=list(map(str,argv)),exit=r.returncode,expected=expected,start=start,end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
			if r.returncode != expected: ready = False; break
		print(row['name'], 'diagnostic stages observed' if ready else 'diagnostic failure at '+stage, flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='DIAGNOSTIC_ONLY',component_sha256=sha(a.component),commands=commands,limitation='The compiler process completed but its recipe dependency changed before receipt sealing. No final qualification or exact-product reuse is claimed. All passing/failing observations remain diagnostic.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
