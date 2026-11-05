#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh replay of all 172 source identities with exact inherited products."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0','O2'), required=True); a = p.parse_args()
	leaf = RUNTIME/('inherited-'+a.mode); build = BUILD/leaf.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	component = Path(read(RUNTIME/'initial.json')['products'][a.mode]['path'])
	identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources','tools') for path,value in identity['identity'][group].items())
	programs = read(PRIOR/'engineering-summary.json')['profiles'][a.mode]['programs']; assert len(programs) == 172
	receipts = {PRIOR/('qualified-v1-'+a.mode)/'observations/commands.json'}
	receipts.update(Path(row['prior_execution_receipt']) for row in programs if 'prior_execution_receipt' in row)
	index = {}
	for path in receipts:
		for command in read(path):
			for word in command['argv']: index.setdefault(word, []).append((path, command))
	commands = []; rows = []; env = dict(os.environ, CCACHE_DISABLE='1'); env.pop('LD_PRELOAD',None); env.pop('VALGRIND_OPTS',None)
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=build,capture_output=True,env=env,timeout=120)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); return r
	for ordinal,row in enumerate(programs):
		products = row.get('products',row.get('qualified_products'))
		assert all(sha(s['path']) == s['sha256'] for s in row['sources'])
		assert all(sha(product['path']) == product['sha256'] for product in products.values())
		raw = products['raw']; candidates = [(p,c) for p,c in index[raw['path']] if any(word.endswith('llvm-raw') for word in c['argv'])]
		assert candidates, row['name']; receipt,command = candidates[0]; argv = command['argv'].copy(); argv[0] = str(component)
		path = build/(str(ordinal)+'.raw.ll'); argv[argv.index(raw['path'])] = str(path)
		assert run(argv,str(ordinal)+'-emit').returncode == 0
		assert sha(path) == raw['sha256'], row['name']
		assert run(['opt','-passes=verify','-disable-output',path],str(ordinal)+'-verify').returncode == 0
		elf = products.get('native',products.get('executable'))
		candidates = [(p,c) for p,c in index[elf['path']] if c['argv'] == [elf['path']] and c['exit'] >= 0]
		assert candidates,row['name']; execution_receipt,execution = candidates[0]
		r = run([elf['path']],str(ordinal)+'-execute'); assert r.returncode == execution['exit']
		assert sha(leaf/(str(ordinal)+'-execute.stdout')) == execution['stdout_sha256']
		assert sha(leaf/(str(ordinal)+'-execute.stderr')) == execution['stderr_sha256']
		rows.append(dict(name=row['name'],sources=row['sources'],fresh_raw=dict(path=str(path),sha256=sha(path)),qualified_products=products,exit=r.returncode,prior_receipt=str(execution_receipt),prior_receipt_sha256=sha(execution_receipt)))
		(leaf/'programs.json').write_text(json.dumps(rows,indent=2)+'\n')
		print(a.mode,ordinal,row['name'],'EXACT_IR FRESH_EXECUTION',flush=True)
	assert len({tuple(s['sha256'] for s in row['sources']) for row in rows}) == 172
	(leaf/'result.json').write_text(json.dumps(dict(status='INHERITED_REPLAY_PASS',mode=a.mode,component_sha256=sha(component),programs=rows,commands=commands,limitation='Unmodified predecessor emitter reused by exact source/tool/product identity. Fresh LLVM emission/verification and ELF execution; prior C0/ABI/memory qualification remains historically attributed. No new member-call implementation or milestone PASS is claimed.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
