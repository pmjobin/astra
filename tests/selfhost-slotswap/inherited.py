#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Re-emit each of 159 identities; reuse only byte-identical qualified products."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import xml.etree.ElementTree as ET
from state import ROOT, RUNTIME, BUILD, PRIOR, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0','O2'), required=True); a = p.parse_args()
	leaf = RUNTIME/('inherited-v2-'+a.mode); build = BUILD/('inherited-v2-'+a.mode); leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	identity = read(a.component.with_suffix('.identity.json')); assert identity['sha256'] == sha(a.component)
	assert all(sha(path) == value for group in ('sources','tools') for path,value in identity['identity'][group].items())
	old = read(PRIOR/'engineering-summary.json')['profiles'][a.mode]; programs = old['programs']; assert len(programs) == 159
	index = {}
	for path in PRIOR.glob('final-v2-*/**/commands.json'):
		for command in read(path):
			for word in command['argv']: index.setdefault(word, []).append((path,command))
	commands = []; results = []; env = dict(os.environ, CCACHE_DISABLE='1'); env.pop('VALGRIND_OPTS',None); env.pop('LD_PRELOAD',None)
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)], cwd=build, capture_output=True, env=env, timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); return r
	for ordinal,row in enumerate(programs):
		assert all(sha(source['path']) == source['sha256'] for source in row['sources']) and all(sha(product['path']) == product['sha256'] for product in row['products'].values())
		raw = row['products']['raw']; candidates = [(p,c) for p,c in index[raw['path']] if any(word.endswith('llvm-raw') for word in c['argv'])]
		assert candidates, row['name']; origin,command = candidates[0]; argv = command['argv'].copy(); argv[0] = str(a.component)
		path = build/(str(ordinal)+'-'+row['name']+'.raw.ll'); argv[argv.index(raw['path'])] = str(path)
		assert run(argv,str(ordinal)+'-emit').returncode == 0
		assert sha(path) == raw['sha256'], ('changed inherited LLVM requires fresh full qualification',row['name'])
		assert run(['opt','-passes=verify','-disable-output',path],str(ordinal)+'-verify').returncode == 0
		elf = row['products'].get('native', row['products'].get('executable')); candidates = [(p,c) for p,c in index[elf['path']] if c['argv'] == [elf['path']] and c['exit'] >= 0]
		assert candidates, row['name']; receipt,execution = candidates[0]
		r = run([elf['path']],str(ordinal)+'-execute'); assert r.returncode == execution['exit']
		assert sha(leaf/(str(ordinal)+'-execute.stdout')) == execution['stdout_sha256'] and sha(leaf/(str(ordinal)+'-execute.stderr')) == execution['stderr_sha256']
		memory = None
		if any(b'swap(' in Path(s['path']).read_bytes() for s in row['sources']):
			xml = leaf/(str(ordinal)+'.xml'); r = run(['valgrind','--command-line-only=yes','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all','--xml=yes','--xml-file='+str(xml),elf['path']],str(ordinal)+'-memory')
			assert r.returncode == execution['exit'] and ET.parse(xml).getroot().find('error') is None
			memory = dict(xml_sha256=sha(xml),errors=0)
		results.append(dict(name=row['name'],sources=row['sources'],fresh_raw=dict(path=str(path),sha256=sha(path)),qualified_products=row['products'],actual_exit=execution['exit'],fresh_memory=memory,qualification='FRESH_CHECKED_TO_LLVM_AND_EXECUTION; exact prior object/ELF/C0/ABI qualification reused because raw LLVM, sources and toolchain match',prior_execution_receipt=str(receipt),prior_execution_receipt_sha256=sha(receipt)))
		(leaf/'programs.json').write_text(json.dumps(results,indent=2)+'\n'); print(a.mode,ordinal,row['name'],'EXACT_IR FRESH_EXECUTION',flush=True)
	assert len({tuple(s['sha256'] for s in row['sources']) for row in results}) == 159
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,component_sha256=sha(a.component),programs=results,original_source_statuses=old['original_source_statuses'],historical_status_classification='PRESERVED; fresh source-status query is a separate gate',commands=commands,recipe_sha256=sha(__file__)),indent=2)+'\n')


if __name__ == '__main__':
	main()
