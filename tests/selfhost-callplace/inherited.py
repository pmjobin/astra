#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Re-emit and execute all 172 inherited source identities with the changed compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, PRIOR, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); p.add_argument('--version',default='v1'); p.add_argument('--resume',action='store_true'); a = p.parse_args()
	leaf = RUNTIME/('inherited-'+a.version+'-'+a.mode); build = BUILD/leaf.name; leaf.mkdir(exist_ok=a.resume); build.mkdir(exist_ok=a.resume)
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == expected for group in ('sources','tools') for path,expected in identity['identity'][group].items())
	programs = read(PRIOR/'engineering-summary.json')['profiles'][a.mode]['programs']; assert len(programs) == 172
	receipts = {PRIOR/('qualified-v1-'+a.mode)/'observations/commands.json'}
	receipts.update(Path(row['prior_execution_receipt']) for row in programs if 'prior_execution_receipt' in row)
	index = {}
	for receipt in receipts:
		for command in read(receipt):
			for word in command['argv']: index.setdefault(word,[]).append((receipt,command))
	commands = read(leaf/'commands.json') if a.resume else []; rows = read(leaf/'programs.json') if a.resume else []; env = dict(os.environ,CCACHE_DISABLE='1'); env.pop('LD_PRELOAD',None); env.pop('VALGRIND_OPTS',None)
	def run(argv,name):
		name = str(len(commands))+'-'+name; start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=build,capture_output=True,env=env,timeout=180)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); return r
	for ordinal,row in enumerate(programs):
		if ordinal < len(rows):
			assert rows[ordinal]['name'] == row['name'] and all(sha(p['path']) == p['sha256'] for p in rows[ordinal]['fresh_products'].values()); continue
		products = row.get('products',row.get('qualified_products'))
		assert all(sha(s['path']) == s['sha256'] for s in row['sources'])
		assert all(sha(product['path']) == product['sha256'] for product in products.values())
		raw = products['raw']; receipt,command = next((p,c) for p,c in index[raw['path']] if any(word.endswith('llvm-raw') for word in c['argv']))
		argv = command['argv'].copy(); argv[0] = str(a.component)
		path = build/(str(ordinal)+'.raw.ll'); argv[argv.index(raw['path'])] = str(path)
		assert run(argv,str(ordinal)+'-emit').returncode == 0,row['name']
		assert run(['opt','-passes=verify','-disable-output',path],str(ordinal)+'-verify').returncode == 0
		obj = build/(str(ordinal)+'.o'); elf = build/str(ordinal)
		object_argv = [word.replace('llvm-raw','emit-obj') if word.endswith('llvm-raw') else str(obj) if word == str(path) else word for word in argv]
		assert run(object_argv,str(ordinal)+'-object').returncode == 0
		old_elf = products.get('native',products.get('executable'))
		old_object = products['object']['path']
		links = [c for _,c in index[old_elf['path']] if '-o' in c['argv'] and c['argv'][c['argv'].index('-o')+1] == old_elf['path'] and old_object in c['argv']]
		assert links,row['name']
		link = [str(obj) if word == old_object else str(elf) if word == old_elf['path'] else word for word in links[0]['argv']]
		assert run(link,str(ordinal)+'-link').returncode == 0
		execution_receipt,execution = next((p,c) for p,c in index[old_elf['path']] if c['argv'] == [old_elf['path']] and c['exit'] >= 0)
		r = run([elf],str(ordinal)+'-execute'); assert r.returncode == execution['exit'],(row['name'],r.returncode)
		assert hashlib.sha256(r.stdout).hexdigest() == execution['stdout_sha256']
		assert hashlib.sha256(r.stderr).hexdigest() == execution['stderr_sha256']
		rows.append(dict(name=row['name'],sources=row['sources'],fresh_products={key:dict(path=str(p),sha256=sha(p)) for key,p in [('raw',path),('object',obj),('native',elf)]},IR_equal_to_predecessor=sha(path)==raw['sha256'],exit=r.returncode,prior_products=products,prior_receipt=str(execution_receipt),prior_receipt_sha256=sha(execution_receipt)))
		(leaf/'programs.json').write_text(json.dumps(rows,indent=2)+'\n'); print(a.mode,ordinal,row['name'],'FRESH_LLVM ELF_MATCH',flush=True)
	assert len({tuple(s['sha256'] for s in row['sources']) for row in rows}) == 172
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,component_sha256=sha(a.component),programs=rows,commands=commands,limitation='All LLVM/object/ELF products freshly generated with the changed compiler. Expected behavior and independent C0/ABI/memory controls remain attributed to exact inherited qualification; new CALLPLACE programs have separate fresh independent qualification.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
