#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Executed checked-type/oracle comparisons with source-bound raw receipts."""
import argparse
from collections import Counter
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import time
from build import ROOT, build, sha


def decode(data):
	result=dict(types={},symbols={},declarations={},uses=[],references=[],signatures={})
	for line in data.decode().splitlines():
		x=line.split()
		if not x: continue
		if x[0]=='ERROR': result['error']=(bytes.fromhex(x[1]).decode(),int(x[2]),int(x[3]),bytes.fromhex(x[4]).decode())
		elif x[0]=='T': result['types'][int(x[1])]=dict(kind=int(x[2]),nominal=int(x[3]),extent=int(x[4]),depth=int(x[5]),name=bytes.fromhex(x[6]).decode(),args=[tuple(map(int,v.split(':'))) for v in x[7:]])
		elif x[0]=='Y': result['symbols'][int(x[1])]=tuple(map(int,x[2:]))
		elif x[0]=='D': result['declarations'][int(x[1])]=dict(span=(bytes.fromhex(x[2]).decode(),int(x[3]),int(x[4])),name=bytes.fromhex(x[5]).decode(),kind=int(x[7]),owner=int(x[10]),node=int(x[-1]))
		elif x[0]=='U': result['uses'].append(dict(node=int(x[1]),span=(bytes.fromhex(x[2]).decode(),int(x[3]),int(x[4])),type=int(x[5]),flags=int(x[6]),deferred=int(x[7]),kind=int(x[8])))
		elif x[0]=='R': result['references'].append(dict(span=(bytes.fromhex(x[2]).decode(),int(x[3]),int(x[4])),state=int(x[5]),target=int(x[6]),reason=int(x[10])))
		elif x[0]=='F': result['signatures'][int(x[1])]=tuple(map(int,x[2:]))
	return result


def expectation(observed,item):
	if item.get('error'):
		assert 'error' in observed,(item['name'],'negative accepted')
		if 'error' in item['marks']: assert observed['error'][:3]==tuple(item['marks']['error']),(item['name'],'authored diagnostic span',observed['error'],item['marks']['error'])
		return
	assert 'error' not in observed,(item['name'],observed.get('error'))
	for mark,expected in item.get('types',{}).items():
		span=tuple(item['marks'][mark]);types=[]
		for n,d in observed['declarations'].items():
			if d['span']==span: types.append(observed['symbols'][n][0])
		for u in observed['uses']:
			if u['span']==span: types.append(u['type'])
		for r in observed['references']:
			if r['span']==span and r['state']==1: types.append(observed['symbols'][r['target']][0])
		assert types and all(t and observed['types'][t]['name']==expected for t in types),(item['name'],mark,expected,types)
	for reason in item.get('required_deferred',[]): assert any(u['deferred']==reason for u in observed['uses']),(item['name'],'missing explicit contract deferral',reason)
	if item.get('closed_reason'):
		assert not any(r['state']==5 and r['reason']==item['closed_reason'] for r in observed['references']),(item['name'],'unclosed edge')
	for expected in item.get('metadata',[]):
		found=[n for n,d in observed['declarations'].items() if d['name']==expected['name'] and d['kind']==expected['kind']]
		assert found and all(observed['symbols'][n][1]==expected['flags'] for n in found),(item['name'],'qualifier metadata',expected)
	if item.get('effect_flags'):assert any(sig[3]&item['effect_flags']==item['effect_flags'] for sig in observed['signatures'].values()),(item['name'],'effect metadata')
	if item.get('callable_result_flags'):assert any(row['kind'] in (25,26) and row['args'] and row['args'][0][1]==item['callable_result_flags'] for row in observed['types'].values()),(item['name'],'callable channel erased')
	for first,second in item.get('same',[]):
		def marked_type(mark):
			n=next(n for n,d in observed['declarations'].items() if d['span']==tuple(item['marks'][mark]));return observed['symbols'][n][0]
		assert marked_type(first)==marked_type(second)!=0,(item['name'],'canonical route differs')
	keys=[(r['kind'],r['nominal'],r['extent'],tuple(r['args'])) for r in observed['types'].values()]
	assert len(keys)==len(set(keys)), 'duplicate canonical descriptor'
	for t,row in observed['types'].items():
		assert all(0<a<t for a,flags in row['args']) and row['depth']<=128
		if row['nominal']: assert row['nominal'] in observed['declarations']


def oracle_types(observed,oracle):
	by_span={d['span']:n for n,d in observed['declarations'].items()}
	matched=[]
	for symbol in oracle['symbols']:
		if symbol['kind'] not in ('parameter','local','field'): continue
		span=(symbol['file'],symbol['start'],symbol['end'])
		if span not in by_span: continue
		n=by_span[span];t=observed['symbols'][n][0]
		if not t: continue
		name=observed['types'][t]['name']
		# Exact type prefix and its following name delimiter; qualifiers are
		# retained and checked separately, never erased from native type rows.
		detail=symbol['detail']
		prefix=detail
		for qualifier in ('owned ','borrowed ','nonnull '):
			if prefix.startswith(qualifier): prefix=prefix[len(qualifier):]
		if name in ('isize','usize'): pass
		if observed['types'][t]['kind']==33:
			parameter=observed['types'][t]['nominal'];owner=observed['declarations'][parameter]['owner']
			params=[i for i,d in observed['declarations'].items() if d['kind']==9 and d['owner']==owner]
			ordinal=params.index(parameter)
			instances=[(n,row['args'][ordinal][0]) for n,row in observed['types'].items() if row['kind']==34 and row['nominal']==owner and ordinal<len(row['args'])]
			matches=[(n,ty) for n,ty in instances if prefix.startswith(observed['types'][ty]['name']+' ')]
			if matches:
				matched.append(dict(span=span,template_type=name,instantiated_type=observed['types'][matches[0][1]]['name'],application=matches[0][0],detail=detail));continue
		assert prefix.startswith(name+' ') or prefix.startswith(name+';'),(symbol,name)
		matched.append(dict(span=span,type=name,detail=detail))
	return matched


def operation_types(observed,item,dump):
	# C0 erases parentheses and folds a signed literal form. Compare only
	# its emitted scalar binary/prefix/short-circuit nodes, with exact types.
	kinds={9:'binary',64:'prefix',70:'short-circuit'}
	actual=Counter()
	for use in observed['uses']:
		if use['kind'] not in kinds or not use['type'] or use['deferred']: continue
		path,start,end=use['span'];text=Path(path).read_bytes()[start:end].decode()
		kind=kinds[use['kind']]
		if kind=='binary' and ('<<' in text or '>>' in text): kind='shift'
		if kind=='binary':
			refs=[r for r in observed['references'] if r['state']==1 and r['span'][0]==path and start<=r['span'][1] and r['span'][2]<=end]
			if len(refs)==2 and all(observed['symbols'][r['target']][0] and observed['types'][observed['symbols'][r['target']][0]]['kind']==32 for r in refs):kind='enum-equality'
		if kind=='prefix' and re.fullmatch(r'[+-]\s*[0-9]+',text): continue
		if kind=='prefix' and use['type'] in (11,12) and re.match(r'[+-]\s*[0-9]',text): continue
		actual[(kind,observed['types'][use['type']]['name'])]+=1
	wanted=Counter((kind,ty) for kind,ty in re.findall(r'\((binary|prefix|short-circuit)\s+\S+\s+: ([^\s)]+)',dump))
	wanted.update(('enum-equality','bool') for _ in re.findall(r'\(enum-(?:equal|not-equal) ',dump))
	wanted.update(('shift',ty) for ty in re.findall(r'\(shift-(?:left|right-arithmetic|right-logical) : ([^\s)]+)',dump))
	assert actual==wanted,(item['name'],'operation type projection',actual,wanted)
	return dict(candidate=sum(actual.values()),oracle=sum(wanted.values()))


def main():
	p=argparse.ArgumentParser()
	for name in ('compiler','build','runtime'): p.add_argument('--'+name,type=Path,required=True)
	p.add_argument('--baseline',type=Path)
	p.add_argument('--mode',action='append');p.add_argument('--no-memory',action='store_true')
	a=p.parse_args();resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	assert not a.build.resolve().is_relative_to(ROOT) and not a.runtime.resolve().is_relative_to(ROOT)
	a.runtime.mkdir(parents=True,exist_ok=True);attempt=a.runtime/('attempt-'+str(time.time_ns()));attempt.mkdir()
	if a.baseline is None:
		a.baseline=attempt/'baseline'
		r=subprocess.run(['python3','-B',Path(__file__).with_name('freeze.py'),'--compiler',a.compiler,'--runtime',a.baseline],capture_output=True)
		(attempt/'freeze.stdout').write_bytes(r.stdout);(attempt/'freeze.stderr').write_bytes(r.stderr);assert r.returncode==0
	(attempt/'harness.json').write_text(json.dumps({str(p):sha(p) for p in (Path(__file__),Path(__file__).with_name('build.py'),Path(__file__).with_name('corpus.py'),Path(__file__).with_name('freeze.py'))},indent=2)+'\n')
	entries=json.loads((a.baseline/'frozen.json').read_text())
	assert all(sha(path)==h for item in entries for path,h in item['sha256'].items())
	(attempt/'frozen.json').write_bytes((a.baseline/'frozen.json').read_bytes())
	commands=[];started=time.monotonic()
	def capture(argv,name,expected=0,details=None):
		if argv is None: commands.append(dict(name=name,reused=True,details=details));return b''
		argv=list(map(str,argv));begin=time.monotonic()
		r=subprocess.run(['/usr/bin/time','-v',*argv],capture_output=True,cwd=a.build,env=dict(os.environ,CCACHE_DISABLE='1',PYTHONDONTWRITEBYTECODE='1'),timeout=1800)
		(attempt/(name+'.stdout')).write_bytes(r.stdout);(attempt/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=argv,exit=r.returncode,seconds=time.monotonic()-begin,stdout_sha256=hashlib.sha256(r.stdout).hexdigest()))
		(attempt/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
		assert expected is None or r.returncode==expected,(name,r.returncode,r.stdout[-1000:],r.stderr[-1000:])
		return r.stdout
	modes=a.mode or ('O0','O2');products=build(a.compiler.resolve(),a.build.resolve(),capture,modes)
	(attempt/'products.json').write_text(json.dumps(products,indent=2)+'\n')
	rows=[];observations={};failures=[]
	for item in entries:
		try:
			name=item['name'];capture([a.compiler,'--parse',*item['paths']],name+'-C0-parse');oracle=json.loads(capture([a.compiler,'--tooling-index',*item['paths']],name+'-C0-index',None))
			dump=capture([a.compiler,'--dump-semantics',*item['paths']],name+'-C0-dump',None).decode()
			assert (not oracle['diagnostics'])==(item['category']=='A'),(name,'C0 category changed')
			for mode in modes:
				exe=a.build/('astra-types-'+mode)
				data=capture([exe,'--types',*item['paths']],name+'-'+mode,1 if item.get('error') else 0);observed=decode(data)
				expectation(observed,item)
				if item.get('error'):
					d=oracle['diagnostics'][0];assert observed['error'][:3]==(d['file'],d['start'],d['end']),(name,'diagnostic span',observed['error'],d)
				elif item['category']=='A':
					matched=oracle_types(observed,oracle)
					operations=operation_types(observed,item,dump)
					rows.append(dict(name=name,mode=mode,matched_types=matched,operations=operations,deferrals=dict(Counter(u['deferred'] for u in observed['uses'] if u['deferred']))))
				if mode==modes[0]: observations[name]=data
				else: assert data==observations[name],(name,'O0/O2 divergence')
			print(name,'PASS',flush=True)
		except (AssertionError,KeyError) as e:
			failures.append(dict(name=item['name'],error=str(e)));print(item['name'],'FAIL',str(e)[:500],flush=True)
	(attempt/'comparisons.json').write_text(json.dumps(rows,indent=2)+'\n')
	(attempt/'failures.json').write_text(json.dumps(failures,indent=2)+'\n')
	assert not failures,failures
	case=next(i for i in entries if i['name']=='calls');original=decode(observations['calls']);killed=[]
	for fault in ('type-name','symbol-signedness','drop-type'):
		mutant=copy.deepcopy(original)
		local=next(n for n,d in mutant['declarations'].items() if d['span']==tuple(case['marks']['v']))
		if fault=='type-name': mutant['types'][1]['name']='u32'
		elif fault=='symbol-signedness': mutant['symbols'][local]=(6,*mutant['symbols'][local][1:])
		else: mutant['symbols'][local]=(0,*mutant['symbols'][local][1:])
		try: expectation(mutant,case)
		except AssertionError: killed.append(fault)
		else: raise AssertionError(('surviving result corruption',fault))
	(attempt/'result-mutations.json').write_text(json.dumps(killed,indent=2)+'\n')
	for mode in modes:
		exe=a.build/('astra-types-'+mode)
		assert capture([exe,'--lifetime'],mode+'-lifetime')==b'TYPECORE_LIFETIME_OK\n'
		case=next(i for i in entries if i['name']=='calls')
		for mutation in ('--mutate-use','--mutate-signature'): assert capture([exe,mutation,*case['paths']],mode+mutation)==b'MUTANT_REJECTED\n'
		capture([exe,'--partial',*case['paths']],mode+'-partial',1)
		assert b'ERROR ' in capture([exe,'--mutate-ast',*case['paths']],mode+'-mutate-ast',1)
		for operation,mark in (('--type-at','read'),('--signature',None)):
			path,start,end=case['marks']['read'];offset=start if mark else 4
			out=capture([exe,operation,path,offset,*case['paths']],mode+operation)
			assert b'QUERY absent' not in out and b'QUERY signature 0' not in out
		if not a.no_memory:
			for name in ('calls','bad-return','bad-arity','aggregate','generic','slots','bad-nonnull-null','owner-needs-flow'):
				item=next(i for i in entries if i['name']==name)
				capture(['valgrind','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=97',exe,'--types',*item['paths']],mode+'-memory-'+name,1 if item.get('error') else 0)
			capture(['valgrind','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=97',exe,'--lifetime'],mode+'-memory-lifetime')
			capture(['valgrind','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=97',exe,'--partial',*case['paths']],mode+'-memory-partial',1)
	(attempt/'result.json').write_text(json.dumps(dict(status='PASS',seconds=time.monotonic()-started,cases=len(entries),modes=modes,commands=len(commands)),indent=2)+'\n')
	print(attempt)


if __name__=='__main__': main()
