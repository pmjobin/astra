#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent source/state oracles, full C0 comparisons and actual host queries."""
import argparse
from collections import Counter
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
from build import ROOT, build, sha


def decode(data):
	result=dict(events={},states={},loans={},active=[],errors=[],deferrals=[],proofs=[],graphs={},origins={},slots=[])
	for line in data.decode().splitlines():
		x=line.split()
		if not x:
			continue
		if x[0]=='ORIGIN':
			result['origins'][int(x[1])]=int(x[2])
		if x[0]=='S':
			result['slots'].append(dict(symbol=int(x[3]),span=(bytes.fromhex(x[7]).decode(),int(x[8]),int(x[9]))))
		if x[0]=='STATUS':
			result['status']=int(x[1])
			result['unmodeled']=int(x[2])
		if x[0]=='G':
			result['graphs'][int(x[1])]=list(map(int,x[2:]))
		if x[0]=='ERROR':
			result['errors'].append((x[1],bytes.fromhex(x[2]).decode(),int(x[3]),int(x[4])))
		if x[0]=='CHECKED_ERROR':
			result['checked_error']=(bytes.fromhex(x[1]).decode(),int(x[2]),int(x[3]),bytes.fromhex(x[4]).decode())
		if x[0]=='DEFER':
			result['deferrals'].append(x[1])
		if x[0]=='E':
			result['events'][tuple(map(int,x[1:3]))]=dict(op=int(x[3]),slot=int(x[4]),next=int(x[5]),other=int(x[6]),region=int(x[7]),call=int(x[8]),span=(bytes.fromhex(x[9]).decode(),int(x[10]),int(x[11])))
		if x[0]=='STATE':
			result['states'][tuple(map(int,x[1:3]))]=tuple(map(int,x[3:]))
		if x[0]=='L':
			result['loans'][tuple(map(int,x[1:3]))]=dict(source=int(x[3]),borrower=int(x[4]),region=int(x[5]),call=int(x[6]),span=(bytes.fromhex(x[7]).decode(),int(x[8]),int(x[9])))
		if x[0]=='ACTIVE':
			result['active'].append(tuple(map(int,x[1:])))
		if x[0]=='PROOF':
			result['proofs'].append((int(x[1]),int(x[2]),int(x[3])))
	assert 'status' in result,'missing native status'
	return result


def expectation(observed,item):
	for mark,bits in item.get('origins',{}).items():
		symbols=[s['symbol'] for s in observed['slots'] if s['span']==tuple(item['marks'][mark])]
		assert symbols and all(observed['origins'].get(s)==bits for s in symbols),(item['name'],'Class origin facts',mark,bits,symbols)
	if item.get('deferred'):
		assert observed['status'] in (1,3),(item['name'],'deferred became safe')
		if 'checked_error' not in observed:
			assert item['deferred'] in observed['deferrals'],(item['name'],'named frontier lost',observed['deferrals'])
		return
	assert 'checked_error' not in observed,(item['name'],'not an ownership witness',observed.get('checked_error'))
	if item.get('error'):
		assert observed['status']==1 and observed['errors'],(item['name'],'negative accepted')
		assert observed['errors'][0][0]==item['error'],(item['name'],'fault classification',observed['errors'])
		if 'error' in item['marks']:
			assert tuple(observed['errors'][0][1:])==tuple(item['marks']['error']),(item['name'],'source diagnostic span',observed['errors'][0],item['marks']['error'])
	else:
		assert observed['status']==0 and not observed['errors'] and not observed['deferrals'],(item['name'],'positive not proved',observed['errors'],observed['deferrals'])
	for mark,state in item.get('states',{}).items():
		span=tuple(item['marks'][mark])
		found=[]
		for key,event in observed['events'].items():
			if event['span']==span and key in observed['states']:
				found.append(observed['states'][key][1])
		assert found and state in found,(item['name'],'independent state',mark,state,found)
	for key,event in observed['events'].items():
		if event['op']==11:
			assert event['next'] and (key[0],event['next']) in observed['events']
		for target in ('next','other'):
			if event[target]:
				assert (key[0],event[target]) in observed['events']
	for function,block,loan in observed['active']:
		assert (function,block) in observed['events'] and (function,loan) in observed['loans']
	assert all(reason==19 or not proved for node,reason,proved in observed['proofs']),'closed an unrelated proof boundary'


def reference_fault(data):
	m=re.search(r'(?m)^(.+):(\d+):(\d+): error: (.+)$',data.decode())
	assert m,'missing enforcing diagnostic'
	path,line,col,message=m.groups()
	raw=Path(path).read_bytes()
	lines=raw.splitlines(keepends=True)
	return dict(path=path,offset=sum(map(len,lines[:int(line)-1]))+int(col)-1,message=message)


def enforcing_reference(stage, exit_code, stderr, item, baseline):
	assert stage=='--check','a tooling/parse receipt cannot establish ownership safety'
	assert bool(exit_code)==bool(item.get('error') or item.get('c0_reject')),(item['name'],'C0 oracle drift')
	assert stderr==(baseline/item['name']/'--check.stderr').read_bytes(),(item['name'],'frozen C0 diagnostic drift')


def main():
	p=argparse.ArgumentParser()
	p.add_argument('--compiler',type=Path,required=True)
	p.add_argument('--build',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	p.add_argument('--baseline',type=Path)
	p.add_argument('--no-memory',action='store_true')
	p.add_argument('--mode',action='append')
	a=p.parse_args()
	a.runtime.mkdir(parents=True,exist_ok=True)
	attempt=a.runtime/('run-'+str(time.time_ns()))
	attempt.mkdir()
	rows=[]
	def capture(argv,name,details=None):
		if argv is None:
			(attempt/(name+'.json')).write_text(json.dumps(details,indent=2)+'\n')
			return b''
		start=time.monotonic()
		r=subprocess.run(['/usr/bin/time','-v','-o',str(attempt/(name+'.time.log')),*map(str,argv)],cwd=ROOT,capture_output=True,env=dict(os.environ,CCACHE_DISABLE='1'))
		(attempt/(name+'.stdout')).write_bytes(r.stdout)
		(attempt/(name+'.stderr')).write_bytes(r.stderr)
		row=dict(name=name,argv=list(map(str,argv)),exit=r.returncode,seconds=time.monotonic()-start,peak_rss_kib=int(re.search(r'Maximum resident set size \(kbytes\): (\d+)',(attempt/(name+'.time.log')).read_text())[1]))
		rows.append(row)
		(attempt/(name+'.json')).write_text(json.dumps(row,indent=2)+'\n')
		return r
	def build_capture(argv,name,details=None):
		if argv is None:
			return capture(None,name,details)
		r=capture(argv,name)
		assert r.returncode==0,r.stderr.decode()[-4000:]
		return r.stdout
	if a.baseline is None:
		a.baseline=attempt/'frozen'
		r=capture([os.sys.executable,'-B',ROOT/'tests/selfhost-ownflow/freeze.py','--compiler',a.compiler,'--runtime',a.baseline],'freeze')
		assert r.returncode==0,r.stderr
	entries=json.loads((a.baseline/'frozen.json').read_text())
	assert sha(a.compiler)==json.loads((a.baseline/'compiler.json').read_text())['sha256']
	for item in entries:
		for path,digest in item['sha256'].items():
			assert sha(path)==digest,'frozen source drift'
	products=build(a.compiler.resolve(),a.build.resolve(),build_capture,a.mode or ('O0','O2'))
	comparisons=[]
	failures=[]
	counts=Counter()
	native_results={}
	try:
		for item in entries:
			reference=capture([a.compiler,'--check',*item['paths']],item['name']+'-c0-check')
			enforcing_reference('--check',reference.returncode,reference.stderr,item,a.baseline)
			fault=reference_fault(reference.stderr) if reference.returncode else None
			observations=[]
			for mode in a.mode or ('O0','O2'):
				exe=a.build/('astra-flow-'+mode)
				r=capture([exe,'--flow',*item['paths']],item['name']+'-'+mode)
				o=decode(r.stdout)
				assert o['status']==r.returncode,(item['name'],'exit/status mismatch')
				observations.append(r.stdout)
				try:
					expectation(o,item)
				except AssertionError as error:
					failures.append(str(error))
				native_results[(item['name'],mode)]=o
			if len(observations)==2:
				assert observations[0]==observations[1],(item['name'],'optimization changed analysis')
			comparisons.append(dict(name=item['name'],c0_exit=reference.returncode,c0_fault=fault,native_errors=o['errors'],native_checked_error=o.get('checked_error'),native_deferrals=o['deferrals'],status=o['status']))
			counts['deferred' if item.get('deferred') else 'negative' if item.get('error') else 'positive']+=1
			print(item['name'],o['status'],o['errors'][:1],o['deferrals'][:3],o.get('checked_error'),flush=True)
			# Separate observation-corruption controls, independent of the native mutators.
		controls=0
		for name,change in [('read',lambda o:o['states'].clear()),('read',lambda o:o['states'].update({k:(v[0],2,v[2]) for k,v in o['states'].items()})),('release-twice',lambda o:o['errors'].clear()),('read',lambda o:o.update(status=1))]:
			item=next(x for x in entries if x['name']==name)
			o=copy.deepcopy(native_results[(name,(a.mode or ['O0'])[0])])
			change(o)
			try:
				expectation(o,item)
			except AssertionError:
				controls+=1
		assert controls==4
		item=next(x for x in entries if x['name']=='release-twice')
		oracle_controls=0
		tooling=next(row for row in json.loads((a.baseline/'commands.json').read_text()) if row['argv'][1]=='--tooling-index' and row['argv'][2:]==item['paths'])
		assert tooling['exit']==0,'expected real non-enforcing tooling acceptance'
		for stage in ('--tooling-index','--check'):
			try:
				enforcing_reference(stage,tooling['exit'],(a.baseline/item['name']/'--tooling-index.stderr').read_bytes(),item,a.baseline)
			except AssertionError:
				oracle_controls+=1
		assert oracle_controls==2
		(attempt/'oracle-controls.json').write_text(json.dumps(dict(rejected=oracle_controls,real_tooling_receipt=tooling,substitutions=['wrong enforcing stage','forged check label with tooling success']),indent=2)+'\n')
		for mode in a.mode or ('O0','O2'):
			exe=a.build/('astra-flow-'+mode)
			for command,case in [('--mutate-backedge','loop-rearm'),('--mutate-owner','call-distinct'),('--mutate-loan-end','call-aliases'),('--mutate-span','read'),('--mutate-function','class-owner'),('--mutate-ordinal','read')]:
				item=next(x for x in entries if x['name']==case)
				r=capture([exe,command,*item['paths']],command[2:]+'-'+mode)
				assert r.returncode==0 and r.stdout==b'MUTANT_REJECTED\n',(command,r.stderr)
			item=next(x for x in entries if x['name']=='read')
			path,start,end=item['marks']['read']
			r=capture([exe,'--owner-at',path,str(start),path],'owner-at-'+mode)
			assert r.returncode==0 and re.search(rb'(?m)^QUERY_OWNER \d+ \d+ \d+ 1$',r.stdout),r.stdout
			r=capture([exe,'--loan-at',path,str(start),path],'loan-at-'+mode)
			assert r.returncode==0 and b'QUERY_OWNER' in r.stdout and b'QUERY_LOAN' in r.stdout,r.stdout
			r=capture([exe,'--lifetime'],'lifetime-'+mode)
			assert r.returncode==0 and r.stdout==b'FLOW_LIFETIME_OK\n',r.stderr
			if not a.no_memory:
				for case in ['read','loop-rearm','for-rearm','nested-exits','unreachable','pointer','pointer-copy-escape','class-owner','class-double-release','call-loan','multi-source','class-param-copy','buffer-param-escape']:
					item=next(x for x in entries if x['name']==case)
					r=capture(['valgrind','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe,'--flow',*item['paths']],'memory-'+case+'-'+mode)
					assert r.returncode==native_results[(case,mode)]['status'] and b'ERROR SUMMARY: 0 errors' in r.stderr,r.stderr[-4000:]
					assert not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]',r.stderr),r.stderr[-4000:]
				r=capture(['valgrind','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe,'--lifetime'],'memory-lifetime-'+mode)
				assert r.returncode==0 and b'ERROR SUMMARY: 0 errors' in r.stderr,r.stderr[-4000:]
		assert not failures,failures
	finally:
		(attempt/'comparisons.json').write_text(json.dumps(comparisons,indent=2)+'\n')
		(attempt/'failures.json').write_text(json.dumps(failures,indent=2)+'\n')
		(attempt/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
	(attempt/'summary.json').write_text(json.dumps(dict(cases=len(entries),counts=counts,products=products,observation_controls=controls,oracle_receipt_controls=oracle_controls,commands=len(rows)),indent=2)+'\n')
	print('PASS',len(entries),'cases',len(rows),'commands',attempt)


if __name__=='__main__':
	main()
