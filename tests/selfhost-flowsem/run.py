#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute source-bound native facts against frozen, independent C0 outcomes."""
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
	result = dict(errors=[], deferrals=[], proofs=[], nulls=[], fields=[], field_states=[], events={}, graphs={})
	for line in data.decode().splitlines():
		x = line.split()
		if not x:
			continue
		if x[0]=='STATUS':
			result['status'] = int(x[1])
		if x[0]=='ERROR':
			result['errors'].append(x[1])
		if x[0]=='CHECKED_ERROR':
			result['checked_error'] = bytes.fromhex(x[4]).decode()
		if x[0]=='DEFER':
			result['deferrals'].append(x[1])
		if x[0]=='PROOF':
			result['proofs'].append(dict(node=int(x[1]), reason=int(x[2]), proved=int(x[3]), span=(bytes.fromhex(x[4]).decode(), int(x[5]), int(x[6]))))
		if x[0]=='NULL':
			result['nulls'].append(dict(function=int(x[1]), block=int(x[2]), input=int(x[3]), output=int(x[4]), fact=int(x[5]), span=(bytes.fromhex(x[6]).decode(), int(x[7]), int(x[8]))))
		if x[0]=='FIELD':
			result['fields'].append(tuple(map(int,x[1:8])))
		if x[0]=='FIELD_STATE':
			result['field_states'].append(tuple(map(int,x[1:])))
		if x[0]=='E':
			result['events'][tuple(map(int,x[1:3]))] = dict(op=int(x[3]), slot=int(x[4]), next=int(x[5]), other=int(x[6]), span=(bytes.fromhex(x[9]).decode(), int(x[10]), int(x[11])))
		if x[0]=='G':
			result['graphs'][int(x[1])] = list(map(int,x[2:]))
	assert 'status' in result
	return result


def expectation(observed, item):
	if item.get('deferred'):
		assert observed['status'] in (1,3), (item['name'], 'deferred became safe')
		assert 'checked_error' in observed or item['deferred'] in observed['deferrals'], (item['name'], observed['deferrals'])
		assert not any(p['proved'] for p in observed['proofs'])
		return
	if item.get('error')=='CHECKED_ERROR':
		assert observed['status']==1 and 'checked_error' in observed
		return
	assert 'checked_error' not in observed, (item['name'], observed.get('checked_error'))
	if item.get('error'):
		assert observed['status']==1 and item['error'] in observed['errors'], (item['name'], observed['status'], observed['errors'], Counter(observed['deferrals']))
		assert not any(p['proved'] for p in observed['proofs'])
	else:
		assert observed['status']==0 and not observed['errors'] and not observed['deferrals'], (item['name'], observed['status'], observed['errors'], Counter(observed['deferrals']))
	for mark, expected in item.get('nulls', {}).items():
		span = tuple(item['marks'][mark])
		facts = [r['fact'] for r in observed['nulls'] if r['span']==span]
		assert expected in facts, (item['name'], mark, expected, facts)
	for mark, expected in item.get('fields', {}).items():
		span = tuple(item['marks'][mark])
		blocks = {key for key,event in observed['events'].items() if event['op'] in (19,20) and event['span'][0]==span[0] and event['span'][1]<=span[1] and event['span'][2]>=span[2]}
		facts = [row[3] for row in observed['field_states'] if row[:2] in blocks]
		assert expected in facts, (item['name'], mark, expected, facts)
	if not item.get('error'):
		if item['name'] in ('owned-record','owned-move','composition','composition-branch'):
			assert any(p['reason']==20 and p['proved'] for p in observed['proofs']), 'owning aggregate completeness obligation lost'
		assert all(p['proved']==1 for p in observed['proofs']), (item['name'], 'unclosed original obligation', observed['proofs'])


def reference(stage, receipt, item, baseline):
	assert stage=='--check', 'non-enforcing stage'
	assert receipt['compiler_sha256']==json.loads((baseline/'compiler.json').read_text())['sha256']
	assert receipt['sources']==item['sha256'], 'source substitution'
	assert all(sha(p)==h for p,h in item['sha256'].items())
	assert bool(receipt['exit'])==bool(item.get('error') or item.get('c0_reject'))
	assert receipt['stderr_sha256']==sha(baseline/item['name']/'--check.stderr'), 'diagnostic/stage substitution'


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--baseline', type=Path, required=True)
	p.add_argument('--before', type=Path)
	p.add_argument('--mode', action='append')
	p.add_argument('--no-build', action='store_true')
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=True)
	attempt = a.runtime/('run-'+str(time.time_ns()))
	attempt.mkdir()
	rows, results, ledger = [], {}, []
	campaign_start = time.monotonic()
	def capture(argv, name, expected=None):
		argv = list(map(str,argv))
		start = time.monotonic()
		time_log = attempt/(name+'.time.log')
		r = subprocess.run(['/usr/bin/time','-v','-o',str(time_log),*argv], cwd=ROOT, capture_output=True, env=dict(os.environ,CCACHE_DISABLE='1'))
		(attempt/(name+'.stdout')).write_bytes(r.stdout)
		(attempt/(name+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(name=name, argv=argv, exit=r.returncode, seconds=time.monotonic()-start, peak_rss_kib=int(re.search(r'Maximum resident set size \(kbytes\): (\d+)',time_log.read_text())[1])))
		(attempt/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
		if expected is not None:
			assert r.returncode==expected, (name,r.stderr.decode()[-3000:])
		return r
	def build_capture(argv, name, details=None):
		if argv is None:
			(attempt/(name+'.json')).write_text(json.dumps(details,indent=2)+'\n')
			return b''
		return capture(argv, name, 0).stdout
	modes = a.mode or ('O0','O2')
	entries = json.loads((a.baseline/'frozen.json').read_text())
	compiler_sha = sha(a.compiler)
	assert compiler_sha==json.loads((a.baseline/'compiler.json').read_text())['sha256']
	try:
		if not a.no_build:
			warm_start = time.monotonic()
			products = build(a.compiler, a.build, build_capture, modes)
			(attempt/'build-wall.json').write_text(json.dumps(dict(seconds=time.monotonic()-warm_start, note='Exact reuse is recorded per product; cold compiler invocations have separate time/RSS receipts.'),indent=2)+'\n')
			(attempt/'products.json').write_text(json.dumps(products,indent=2)+'\n')
		if a.before is None:
			a.before = attempt/'compat-before'
			a.before.mkdir()
			for item in entries:
				r = capture([a.build/('astra-flow-'+modes[0]),'--compat',*item['paths']],item['name']+'-compat')
				(a.before/(item['name']+'.stdout')).write_bytes(r.stdout)
		for item in entries:
			r = capture([a.compiler,'--check',*item['paths']], item['name']+'-c0', 1 if item.get('error') or item.get('c0_reject') else 0)
			receipt = dict(compiler_sha256=compiler_sha,sources=item['sha256'],exit=r.returncode,stderr_sha256=hashlib.sha256(r.stderr).hexdigest())
			reference('--check', receipt, item, a.baseline)
			(attempt/(item['name']+'-reference.json')).write_text(json.dumps(receipt,indent=2)+'\n')
			observations = []
			for mode in modes:
				exe = a.build/('astra-flow-'+mode)
				r = capture([exe,'--flow',*item['paths']], item['name']+'-'+mode)
				o = decode(r.stdout)
				assert r.returncode==o['status']
				expectation(o,item)
				observations.append(r.stdout)
				results[(item['name'],mode)] = o
			if len(observations)==2:
				assert observations[0]==observations[1], (item['name'],'profile drift')
			before_path = a.before/(item['name']+'.stdout')
			assert before_path.is_file(), 'source-bound pre-change observation required'
			before = decode(before_path.read_bytes())
			after = decode(observations[0])
			keys = {(p['node'],p['reason']) for p in before['proofs']} | {(p['node'],p['reason']) for p in after['proofs']}
			old = {(p['node'],p['reason']):p for p in before['proofs']}
			new = {(p['node'],p['reason']):p for p in after['proofs']}
			ledger.append(dict(name=item['name'],source_sha256=item['sha256'],before_status=before['status'],after_status=after['status'],uses=[dict(node=k[0],reason=k[1],before=old.get(k),after=new.get(k)) for k in sorted(keys)]))
			print(item['name'],after['status'],Counter(p['reason'] for p in after['proofs'] if p['proved']),flush=True)
		controls = []
		positive = next(x for x in entries if x['name']=='guard')
		valid = results[('guard',modes[0])]
		for label in ('null-fact','source-span','closed-proof','source-hash','stage','diagnostic','compiler'):
			try:
				if label in ('null-fact','source-span','closed-proof'):
					bad = copy.deepcopy(valid)
					if label=='null-fact':
						for row in bad['nulls']: row['fact']=3
					if label=='source-span':
						for row in bad['nulls']: row['span']=('wrong-source',0,1)
					if label=='closed-proof':
						for row in bad['proofs']: row['proved']=0
					expectation(bad,positive)
				else:
					receipt = json.loads((attempt/'guard-reference.json').read_text())
					stage = '--tooling-index' if label=='stage' else '--check'
					if label=='source-hash': receipt['sources']={}
					if label=='diagnostic': receipt['stderr_sha256']='0'*64
					if label=='compiler': receipt['compiler_sha256']='0'*64
					reference(stage,receipt,positive,a.baseline)
			except AssertionError:
				controls.append(label)
		assert len(controls)==7
		for mode in modes:
			exe = a.build/('astra-flow-'+mode)
			mutations = set()
			for name in ('overwrite','record','composition-branch','owned-record'):
				item = next(x for x in entries if x['name']==name)
				r = capture([exe,'--mutate-semantic',*item['paths']],'mutate-'+name+'-'+mode,0)
				mutations.update(map(int,re.findall(rb'(?m)^MUTATION (\d+)$',r.stdout)))
			assert set(range(14)) <= mutations, mutations
			for name in ('guard','loop-continue','owned-record','nested','composition-branch','owned-stale','ctor-missing'):
				item = next(x for x in entries if x['name']==name)
				r = capture(['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe,'--flow',*item['paths']], 'memory-'+name+'-'+mode,results[(name,mode)]['status'])
				assert b'ERROR SUMMARY: 0 errors' in r.stderr and not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]',r.stderr)
			for case,option,mark,needle in [('guard','--nonnull-at','ready',rb'(?m)^QUERY_NONNULL 2$'),('record','--field-at','read_a',rb'(?m)^QUERY_FIELD \d+ 1$')]:
				item = next(x for x in entries if x['name']==case)
				path,start,end = item['marks'][mark]
				r = capture([exe,option,path,str(start),*item['paths']],case+'-public-query-'+mode,0)
				assert re.search(needle,r.stdout)
				r = capture([exe,option,'wrong-source',str(start),*item['paths']],case+'-wrong-source-'+mode,0)
				assert re.search(rb'(?m)^QUERY_OWNER 0 0 0 -1$',r.stdout)
			r = capture([exe,'--lifetime'],'lifetime-'+mode,0)
			assert b'FLOWSEM_LIFETIME_OK' in r.stdout
			r = capture(['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe,'--lifetime'],'memory-lifetime-'+mode,0)
			assert b'ERROR SUMMARY: 0 errors' in r.stderr
			for option in ('--limit','--steps'):
				r = capture([exe,option,'1',*positive['paths']],option[2:]+'-'+mode,1)
				assert b'FLOW_RESOURCE_EXHAUSTED' in r.stdout and not any(p['proved'] for p in decode(r.stdout)['proofs'])
		(attempt/'controls.json').write_text(json.dumps(controls,indent=2)+'\n')
		(attempt/'summary.json').write_text(json.dumps(dict(status='PASS',cases=len(entries),counts=dict(Counter('deferred' if x.get('deferred') else 'negative' if x.get('error') else 'positive' for x in entries)),commands=len(rows),active_seconds=time.monotonic()-campaign_start),indent=2)+'\n')
	finally:
		(attempt/'ledger.json').write_text(json.dumps(ledger,indent=2)+'\n')
		(attempt/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
	print('PASS FLOWSEM',attempt)


if __name__=='__main__':
	main()
