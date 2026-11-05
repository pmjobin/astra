#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bounded nonproductive signature cycle and existing finite-recursion deferral."""
import argparse
import json
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--name',default='cycles-final-v3'); a = p.parse_args(); assert a.name.replace('-','').isalnum()
	leaf = RUNTIME/a.name; build = BUILD/a.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	path = leaf/'cycle.astra'; path.write_text('struct First<T> { Second<T> child; }\nstruct Second<U> { First<U> child; }\nint use(First<int> value) { return 0; }\nint main() { return 0; }\n')
	rows = []
	def run(argv,name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],capture_output=True,cwd=ROOT,timeout=30)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(rows,indent=2)+'\n'); print(name,r.returncode,flush=True); return r
	c0 = run([C0,'--check',path],'C0'); assert c0.returncode == 1
	for version in ('baseline','window-v2'):
		component = BUILD/('diagnostic-'+version)/'resource-O0'; result = run([component,path],version)
		assert result.returncode == 1 and any(line.startswith('GENEVENT ') and line.split()[2] == '6' for line in result.stdout.decode().splitlines())
	finite = next(row for row in read(RUNTIME/'corpus-v2/selection.json') if row['name'] == 'finite-runtime-recursion')
	for mode in ('O0','O2'):
		component = BUILD/('native-window-v2-'+mode)/('astra-llvm-'+mode); output = build/(mode+'.o'); output.write_bytes(b'preserved cycle refusal\n'); original = sha(output)
		admission = run([component,'--classstorage-admit',mode,output,path],'cycle-admit-'+mode)
		diagnostics = [bytes.fromhex(line.split()[4]).decode() for line in admission.stdout.decode().splitlines() if line.startswith('CHECKED_ERROR ')]
		assert admission.returncode == 1 and any('recursive generic instantiation' in message for message in diagnostics)
		result = run([component,'--classstorage-emit-obj',mode,output,path],'cycle-'+mode)
		assert result.returncode == 2 and sha(output) == original
		result = run([component,'--classstorage-admit',mode,output,*[s['path'] for s in finite['sources']]],'finite-recursion-'+mode)
		assert result.returncode == 3 and b'DEFER UNSUPPORTED_EFFECT ' in result.stdout
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',cycle_source_sha256=sha(path),commands=rows,disposition='Nonproductive by-value signature cycle is independently C0-rejected and bounded-deferred by Astra. Finite runtime recursion is C0-admitted but remains effect-DEFERRED; neither is an executable success.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
