#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused independent binder/oracle/query validation; preserves every attempt."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import subprocess
import time

from build import ROOT, LIBRARIES, build, sha
from corpus import cases, materialize


def decode(data):
	result = dict(declarations={}, references=[], scopes=[],coverage={})
	for line in data.decode().splitlines():
		x = line.split()
		if not x: continue
		if x[0] == 'ERROR':
			result['error'] = (bytes.fromhex(x[1]).decode(), int(x[2]), int(x[3]), bytes.fromhex(x[4]).decode())
		elif x[0] == 'D':
			n = int(x[1]); path = bytes.fromhex(x[2]).decode(); start, end = map(int, x[3:5])
			result['declarations'][n] = dict(id=f'{path}#{start}:{end}', span=(path,start,end), name=bytes.fromhex(x[5]).decode(), canonical=bytes.fromhex(x[6]).decode(), kind=int(x[7]), domain=int(x[8]), scope=int(x[9]), owner=int(x[10]))
		elif x[0] == 'R':
			result['references'].append(dict(number=int(x[1]), span=(bytes.fromhex(x[2]).decode(),int(x[3]),int(x[4])), state=int(x[5]), target=int(x[6]), alternative=int(x[7]), scope=int(x[8]), domain=int(x[9]), reason=int(x[10])))
		elif x[0] == 'S': result['scopes'].append(list(map(int,x[1:])))
		elif x[0] == 'C': result['coverage'][int(x[1])]=int(x[2])
	return result


def expectation(observed, item, marks):
	if 'error' in item and not item.get('raw_error'):
		assert 'error' in observed, item['name']
		assert observed['error'] == (*marks['error'], item['error']), (item['name'], observed['error'], marks['error'], item['error'])
		return
	if item.get('raw_error'):
		assert 'error' in observed
		return
	assert 'error' not in observed, (item['name'], observed.get('error'))
	declared = observed['declarations']
	for use, declaration in item.get('refs', {}).items():
		path, start, end = marks[use]
		found = [r for r in observed['references'] if r['span'] == (path,start,end) and r['state'] == 1]
		assert any(declared[r['target']]['span'] == marks[declaration] for r in found), (item['name'], use, declaration, found)
	for declaration, shape in item.get('declarations', {}).items():
		rows = [d for d in declared.values() if d['span'] == marks[declaration]]
		assert len(rows) == 1 and (rows[0]['kind'],rows[0]['domain']) == tuple(shape)
	for declaration, owner in item.get('owners', {}).items():
		rows = [d for d in declared.values() if d['span'] == marks[declaration]]
		assert len(rows) == 1 and rows[0]['owner'] in declared and declared[rows[0]['owner']]['span'] == marks[owner], (item['name'], declaration, owner, rows)
	for use, reason in item.get('deferred', {}).items():
		assert any(r['span'] == marks[use] and r['state'] == 5 and r['reason'] == reason and r['target'] == 0 for r in observed['references']), (item['name'], use)
	for r in observed['references']:
		assert r['state'] in (1,5,6)
		assert r['state'] != 1 or r['target'] in declared
	for scope in observed['scopes']:
		assert scope[1] < scope[0]


def correspondence(candidate, oracle):
	declared = candidate['declarations']
	by_id = {d['id']: d for d in declared.values()}
	kinds = {1:'function',2:'constant',3:'struct',4:'class',6:'field',7:'parameter',8:'local',11:'function',12:'function',14:'property',15:'local',18:'function'}
	synthetic = {symbol['id'] for symbol in oracle['symbols'] if symbol['kind']=='local' and symbol['name'] in ('foreach','throw')}
	for symbol in oracle['symbols']:
		if symbol['id'] in synthetic: continue
		assert symbol['id'] in by_id, ('missing C0 declaration',symbol)
		actual = by_id[symbol['id']]
		assert symbol['name'].split('<',1)[0] in (actual['name'], actual['canonical']), (symbol,actual)
		assert kinds.get(actual['kind']) == symbol['kind'], (symbol,actual)
	matched = deferred = 0
	for reference in oracle['references']:
		if reference['id'] in synthetic: continue
		key = (reference['file'], reference['start'], reference['end'])
		rows = [r for r in candidate['references'] if r['span'] == key]
		if any(r['state'] == 5 and r['reason'] in (1,2,3,4,5) for r in rows): deferred += 1; continue
		assert any(r['state'] == 1 and declared[r['target']]['id'] == reference['id'] for r in rows), ('C0 edge', reference, rows)
		matched += 1
	return dict(symbols=len(oracle['symbols'])-len(synthetic), matched=matched, deferred=deferred, synthetic_keyword_temporaries=len(synthetic))


def main():
	p=argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler',type=Path,required=True)
	p.add_argument('--build',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	p.add_argument('--mode',action='append')
	p.add_argument('--no-memory',action='store_true')
	a=p.parse_args()
	resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	compiler, directory, runtime = [v.resolve() for v in (a.compiler,a.build,a.runtime)]
	assert not directory.is_relative_to(ROOT) and not runtime.is_relative_to(ROOT)
	runtime.mkdir(parents=True,exist_ok=True)
	attempt=runtime/('attempt-'+str(time.time_ns())); attempt.mkdir()
	commands=[]; started=time.monotonic()
	harness = {str(path):sha(path) for path in (Path(__file__),Path(__file__).with_name('build.py'),Path(__file__).with_name('corpus.py'))}
	(attempt/'harness.json').write_text(json.dumps(harness,indent=2)+'\n')
	def capture(argv,name,expected=0,details=None):
		if argv is None:
			commands.append(dict(name=name,reused=True,**details)); return b''
		argv=list(map(str,argv)); start=time.monotonic()
		r=subprocess.run(argv,cwd=directory,capture_output=True,timeout=1200,env=dict(os.environ,CCACHE_DISABLE='1',PYTHONDONTWRITEBYTECODE='1'))
		(attempt/(name+'.stdout')).write_bytes(r.stdout); (attempt/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=argv,exit=r.returncode,seconds=time.monotonic()-start,stdout_sha256=hashlib.sha256(r.stdout).hexdigest()))
		(attempt/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
		assert expected is None or r.returncode==expected,(name,r.returncode,r.stderr.decode(errors='replace')[:2000])
		return r.stdout
		# Freeze source bytes, independent target spans and expected errors FIRST.
	entries=[]
	for item in cases():
		leaf=attempt/item['name']; leaf.mkdir()
		files,marks=materialize(item['files']); paths={}
		for name,data in item.get('raw_hex',{}).items(): files[name]=bytes.fromhex(data)
		for name,data in files.items():
			path=leaf/name; path.write_bytes(data); paths[name]=str(path)
		item=dict(item,paths=list(paths.values()),marks={tag:(paths[path],start,end) for tag,(path,start,end) in marks.items()},source_sha256={paths[name]:hashlib.sha256(data).hexdigest() for name,data in files.items()})
		if item['oracle']=='previous':
			item['error'] += '\nprevious declaration: '+paths['a.astra']+':1:5'
		entries.append(item)
	(attempt/'frozen.json').write_text(json.dumps(entries,indent=2)+'\n')
	modes=a.mode or ('O0','O2')
	products=build(compiler,directory,capture,modes)
	(attempt/'products.json').write_text(json.dumps(products,indent=2)+'\n')
	results=[]; observations={}; current_observations={}
	for item in entries:
		name=item['name']; negative='error' in item or item.get('raw_error')
		oracle_data=capture([compiler,'--tooling-index',*item['paths']],name+'-C0',None)
		oracle=json.loads(oracle_data)
		assert commands[-1]['exit']==(0 if item['oracle']=='positive' else 1),(name,'C0 exit')
		if item['oracle']=='positive': assert not oracle['diagnostics'],(name,oracle['diagnostics'])
		if item['oracle'] in ('error','syntax','later','previous'): assert oracle['diagnostics'],(name,'expected independent C0 rejection')
		if item['oracle'] in ('error','previous'):
			d=oracle['diagnostics'][0]
			assert (d['file'],d['start'],d['end'],d['message'])==(*item['marks']['error'],item['error']),(name,d,item['marks']['error'],item['error'])
		for mode in modes:
			data=capture([directory/('astra-bind-'+mode),'--index',*item['paths']],name+'-'+mode,1 if negative else 0)
			observed=decode(data); expectation(observed,item,item['marks'])
			if item['oracle']=='positive': results.append(dict(name=name,mode=mode,**correspondence(observed,oracle)))
			if item['oracle']=='syntax':
				d=oracle['diagnostics'][0]
				assert observed['error']==(d['file'],d['start'],d['end'],d['message'])
			if mode==modes[0]: observations[name]=data
			else: assert data==observations[name],(name,'optimization divergence')
		print(name,'PASS',flush=True)
	(attempt/'correspondence.json').write_text(json.dumps(results,indent=2)+'\n')
	# Mutation controls corrupt target identity/scope exposure/byte origin; the
	# frozen assertions above must reject each. Source import A/B is a seventh.
	import copy
	item=entries[0]; original=decode(observations[item['name']]); killed=[]
	for fault in ('target','span','source','missing','scope-edge','first-spelling'):
		mutant=copy.deepcopy(original)
		row=next(r for r in mutant['references'] if r['span']==item['marks']['readA'])
		if fault=='target': row['target']=next(n for n,d in mutant['declarations'].items() if d['span']==item['marks']['funcB'])
		elif fault=='span': row['span']=(row['span'][0],row['span'][1]+1,row['span'][2]+1)
		elif fault=='source': row['span']=(item['paths'][1],*row['span'][1:])
		elif fault=='missing': mutant['references'].remove(row)
		elif fault=='scope-edge':
			# Redirect one imported edge to the local callable's identity.
			row=next(r for r in mutant['references'] if r['span']==item['marks']['callA']); row['target']=next(n for n,d in mutant['declarations'].items() if d['span']==item['marks']['funcB'])
		else:
			item=next(e for e in entries if e['name']=='sibling-locals'); mutant=decode(observations[item['name']]); row=next(r for r in mutant['references'] if r['span']==item['marks']['r2']); row['target']=next(n for n,d in mutant['declarations'].items() if d['span']==item['marks']['one'])
		try: expectation(mutant,item,item['marks'])
		except AssertionError: killed.append(fault)
		else: raise AssertionError(('surviving mutation',fault))
		item=entries[0]
	(attempt/'mutations.json').write_text(json.dumps(killed,indent=2)+'\n')
	# Exercise actual consumer lookup, reverse lists and retained source owners.
	item=entries[0]
	for mode in modes:
		exe=directory/('astra-bind-'+mode)
		for operation,tag in (('--definition','callA'),('--references','funcA')):
			path,start,end=item['marks'][tag]
			data=capture([exe,operation,path,start,*reversed(item['paths'])],mode+operation)
			assert b'QUERY '+(b'definition' if operation=='--definition' else b'references') in data
			query=decode(data.split(b'QUERY ',1)[1].split(b'\n',1)[1])['references']
			assert query and all(decode(observations[item['name']])['declarations'][r['target']]['span']==item['marks']['funcA'] for r in query)
		capture([exe,'--partial','2',*item['paths']],mode+'-partial',1)
		capture([exe,'--index',item['paths'][0],str(Path(item['paths'][0]).parent)+'/./a.astra'],mode+'-path-alias',2)
		mutated=capture([exe,'--mutate-span',*item['paths']],mode+'-native-span-mutation')
		try: expectation(decode(mutated),item,item['marks'])
		except AssertionError: killed.append(mode+'-native-span-mutation-dump-preserved')
		else: raise AssertionError('native span mutation survived')
		assert capture([exe,'--lifetime'],mode+'-lifetime')==b'BINDER_LIFETIME_OK\nPARSER_LIFETIME_OK\nPARSER_CURSOR_OK\n'
		# The reusable API's original lexer/parser owners are retired before
		# every observation; its own inputs supply a realistic multi-source run.
		inputs=[p for p in json.loads((directory/('astra-bind-'+mode+'.identity.json')).read_text())['identity']['sources'] if p.endswith('.astra')]
		current_data=capture(['/usr/bin/time','-v',exe,'--index',*inputs],mode+'-current-source')
		current_observations[mode]=current_data
		assert current_data==current_observations[modes[0]], 'current-source optimization divergence'
		(attempt/(mode+'-current-summary.json')).write_text(json.dumps(dict(coverage=decode(current_data)['coverage'],declarations=len(decode(current_data)['declarations']),references=len(decode(current_data)['references']),stdout_sha256=hashlib.sha256(current_data).hexdigest()),indent=2)+'\n')
	(attempt/'mutations.json').write_text(json.dumps(killed,indent=2)+'\n')
	for mode in modes:
		exe=directory/('astra-bind-'+mode)
		for name, tag in (('sibling-locals','r1'),('sibling-locals','r2'),('members','select')):
			case=next(e for e in entries if e['name']==name); path,start,end=case['marks'][tag]
			data=capture([exe,'--definition',path,start,*case['paths']],mode+'-query-'+name+'-'+tag)
			rows=decode(data.split(b'QUERY ',1)[1].split(b'\n',1)[1])['references']; assert len(rows)==1
			if name=='members': assert rows[0]['state']==5 and rows[0]['target']==0
			else:
				d=decode(data)['declarations']; expected='one' if tag=='r1' else 'two'; assert d[rows[0]['target']]['span']==case['marks'][expected]
		for name in ('ambiguity','internal-denied'):
			case=next(e for e in entries if e['name']==name); path,start,end=case['marks']['error']
			capture([exe,'--definition',path,start,*case['paths']],mode+'-query-'+name,1)
			# Scale long imports and many declarations in several real source files.
	stress_paths=[]
	for n in range(16):
		path=attempt/f'stress-{n:02d}.astra'; path.write_text(f'namespace N{n};'+''.join(f'int f{i}(){{return {i};}}' for i in range(128))); stress_paths.append(str(path))
	client=attempt/'stress-client.astra'; client.write_text(''.join(f'using N{n};' for n in range(16))+'int client(){return N15.f127();}'); stress_paths.append(str(client))
	long_imports=[]
	for n in range(256):
		path=attempt/f'import-{n:03d}.astra';path.write_text(f'namespace Long{n};int f{n}(){{return {n};}}');long_imports.append(str(path))
	client=attempt/'import-client.astra';client.write_text(''.join(f'using Long{n};' for n in range(256))+'int client(){return f255();}');long_imports.append(str(client))
	deep=attempt/'deep.astra'; deep.write_text('int deep(){'+'if(true){'*96+'int x=1;'+'}'*96+'return 0;}')
	for mode in modes:
		exe=directory/('astra-bind-'+mode)
		capture(['/usr/bin/time','-v',exe,'--index',*stress_paths[:4]],mode+'-stress-small')
		capture(['/usr/bin/time','-v',exe,'--index',*stress_paths],mode+'-stress')
		capture(['/usr/bin/time','-v',exe,'--index',*stress_paths],mode+'-stress-warm')
		capture([exe,'--index',deep],mode+'-deep')
		capture(['/usr/bin/time','-v',exe,'--index',*long_imports],mode+'-long-imports')
		if not a.no_memory:
			assert shutil.which('valgrind'),'memory checker required'
			for name in ('cross-file','ambiguity','nested-collision','unknown-first','unknown-import','members'):
				case=next(e for e in entries if e['name']==name)
				capture(['valgrind','--error-exitcode=99','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe,'--index',*case['paths']],mode+'-memory-'+name,1 if 'error' in case else 0)
			for label,argv,expected in [('deep',['--index',deep],0),('stress',['--index',*stress_paths],0),('partial',['--partial','4',*entries[0]['paths']],1),('lifetime',['--lifetime'],0),('long-imports',['--index',*long_imports],0)]:
				capture(['valgrind','--error-exitcode=99','--leak-check=full','--errors-for-leak-kinds=definite,indirect,possible',exe,*argv],mode+'-memory-'+label,expected)
	assert harness == {path:sha(path) for path in harness}, 'validation harness changed while running'
	result=dict(status='PASS' if not a.no_memory and len(modes)==2 else 'PARTIAL',cases=len(entries),correspondence=results,mutations=killed,modes=modes,products=products,seconds=time.monotonic()-started,process_calls=len([c for c in commands if not c.get('reused')]))
	(attempt/'result.json').write_text(json.dumps(result,indent=2)+'\n')
	print(attempt,flush=True)


if __name__=='__main__': main()
