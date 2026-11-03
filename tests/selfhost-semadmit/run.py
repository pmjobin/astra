#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute frozen admission sources, independent C0 and original proof ledgers."""
import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def decode(data):
	r=dict(proofs={},errors=[],deferrals=[],copies=[],calls=[])
	for line in data.decode().splitlines():
		x=line.split()
		if not x:
			continue
		if x[0]=='STATUS': r['status']=int(x[1])
		if x[0]=='PROOF': r['proofs'][(int(x[1]),int(x[2]),x[4],int(x[5]),int(x[6]))]=int(x[3])
		if x[0]=='ERROR': r['errors'].append(x[1])
		if x[0]=='CHECKED_ERROR': r['errors'].append('CHECKED_ERROR')
		if x[0]=='DEFER': r['deferrals'].append(x[1])
		if x[0]=='COPY': r['copies'].append(x[1:])
		if x[0]=='CALL': r['calls'].append(x[1:])
	return r


def main():
	p=argparse.ArgumentParser()
	for name in ('compiler','build','runtime','baseline'):
		p.add_argument('--'+name,type=Path,required=True)
	p.add_argument('--mode',action='append')
	p.add_argument('--development',action='store_true')
	p.add_argument('--native-only',action='store_true')
	p.add_argument('--supplemental',type=Path)
	p.add_argument('--second-profile-build',type=Path)
	a=p.parse_args()
	a.runtime.mkdir(parents=True,exist_ok=False)
	a.build.mkdir(parents=True,exist_ok=True)
	entries=json.loads((a.baseline/'frozen.json').read_text())
	source_baselines={x['name']:a.baseline for x in entries}
	if a.supplemental:
		for item in json.loads((a.supplemental/'frozen.json').read_text()):
			if item['name'] in source_baselines:
				prior=next(x for x in entries if x['name']==item['name'])
				assert prior['sha256']==item['sha256'],'supplement altered original bytes'
			else:
				entries.append(item)
				source_baselines[item['name']]=a.supplemental
	tools=json.loads((a.baseline/'tools.json').read_text())
	assert sha(a.compiler)==tools[str(a.compiler)]
	rows=[]
	ledger=[]
	def run(argv,name,expected=None):
		argv=list(map(str,argv))
		t=time.monotonic()
		r=subprocess.run(['/usr/bin/time','-v','-o',str(a.runtime/(name+'.time')),*argv],capture_output=True,env=dict(os.environ,CCACHE_DISABLE='1'),cwd=a.build)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(name=name,argv=argv,exit=r.returncode,seconds=time.monotonic()-t))
		(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
		if expected is not None: assert r.returncode==expected,(name,r.returncode,r.stderr.decode()[:2000])
		return r
	try:
		for item in entries:
			item_base=source_baselines[item['name']]
			path=Path(item['paths'][0])
			assert sha(path)==item['sha256']
			c0=run([a.compiler,'--check',path],item['name']+'-c0')
			assert bool(c0.returncode)==bool(item['diagnostic']),(item['name'],c0.stderr.decode())
			assert c0.stderr==(item_base/item['name']/'--check.stderr').read_bytes(),(item['name'],'first diagnostic drift')
			if item['diagnostic']: assert item['diagnostic'] in c0.stderr.decode(),item['name']
			observations=[]
			for mode in a.mode or ('O0','O2'):
				product_dir=a.second_profile_build if mode=='O2' and a.second_profile_build else a.build
				exe=product_dir/('astra-flow-'+mode)
				result=run([exe,'--admit',path],item['name']+'-'+mode)
				o=decode(result.stdout)
				assert result.returncode==o['status']
				print(item['name'],mode,o['status'],o['errors'],dict(Counter(o['deferrals'])),flush=True)
				if a.development: continue
				if item['defer']:
					assert o['status'] in (1,3) and (item['defer'] in o['deferrals'] or 'CHECKED_ERROR' in o['errors'])
				elif item['error']:
					assert o['status']==1 and item['error'] in o['errors'],item['name']
				else:
					assert o['status']==0 and not o['errors'] and not o['deferrals'],item['name']
					assert all(o['proofs'].values()),item['name']
				if o['status']!=0: assert not any(o['proofs'].values()),item['name']
				observations.append(result.stdout)
				legacy=run([exe,'--flow',path],item['name']+'-legacy-'+mode)
				assert legacy.stdout==(item_base/item['name']/'before.stdout').read_bytes(),(item['name'],'legacy drift')
				if item['execute'] and not a.native_only:
					product=a.build/(item['name']+'-'+mode)
					paths=[path]
					if 'int main(' not in path.read_text():
						harness=a.runtime/(item['name']+'-harness.astra')
						harness.write_text('int main(){return 0;}\n')
						paths.append(harness)
					run([a.compiler,'-'+mode,*paths,'-o',product],item['name']+'-compile-'+mode,0)
					run([product],item['name']+'-execute-'+mode,0)
					memory=run(['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',product],item['name']+'-memory-'+mode,0)
					assert b'ERROR SUMMARY: 0 errors' in memory.stderr and not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]',memory.stderr)
			if observations:
				assert all(x==observations[0] for x in observations),'O0/O2 drift'
				before=decode((item_base/item['name']/'before.stdout').read_bytes())
				after=decode(observations[0])
				ledger.append(dict(name=item['name'],sha256=item['sha256'],before_status=before['status'],after_status=after['status'],closed_original=[list(k) for k,v in before['proofs'].items() if not v and after['proofs'].get(k)==1],new_proofs=[list(k) for k,v in after['proofs'].items() if v and k not in before['proofs']],absent_original=[list(k) for k in before['proofs'] if k not in after['proofs']],before=[[list(k),v] for k,v in before['proofs'].items()],after=[[list(k),v] for k,v in after['proofs'].items()]))
		(a.runtime/'summary.json').write_text(json.dumps(dict(cases=len(entries),original_closures=sum(len(x['closed_original']) for x in ledger),admitted=[x['name'] for x in ledger if x['after_status']==0],ledger=ledger),indent=2)+'\n')
		if not a.development:
			for mode in a.mode or ('O0','O2'):
				product_dir=a.second_profile_build if mode=='O2' and a.second_profile_build else a.build
				exe=product_dir/('astra-flow-'+mode)
				mutations=set()
				for name in ('equal-paths','channel-forward','channel-consume','channel-borrow','member-mutates'):
					item=next(x for x in entries if x['name']==name)
					paths=item['paths']
					if name=='member-mutates':
						purity=a.runtime/'forged-purity-control.astra'
						purity.write_text('class Choice{int x;init(){this.x=1;}int read(bool c){if(c){this.x=this.x+1;}else{this.x=this.x+2;}return this.x;}}\n')
						run([a.compiler,'--check',purity],'purity-c0-'+mode,0)
						paths=[purity]
					r=run([exe,'--mutate-admission',*paths],'mutations-'+name+'-'+mode,0)
					mutations.update(map(int,re.findall(rb'(?m)^ADMISSION_MUTATION (\d+)$',r.stdout)))
				assert mutations==set(range(18)),mutations
				destructor=Path(__file__).with_name('destructor.astra')
				r=run([exe,'--admit',destructor],'destructor-deferred-'+mode,3)
				assert not any(decode(r.stdout)['proofs'].values())
				readonly=a.runtime/'readonly-class-negative.astra'
				readonly.write_text('class C{readonly int x;init(){this.x=42;}}int main(){var c=new C();return c.x;}\n')
				r=run([a.compiler,'--check',readonly],'readonly-class-c0-'+mode,1)
				assert b'readonly fields' in r.stderr
				r=run([exe,'--admit',readonly],'readonly-class-deferred-'+mode,3)
				assert not any(decode(r.stdout)['proofs'].values())
				for name in ('equal-paths','nested-channel','channel-overlap','member-mutates'):
					item=next(x for x in entries if x['name']==name)
					r=run(['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe,'--admit',*item['paths']],'native-memory-'+name+'-'+mode)
					assert r.returncode==decode(r.stdout)['status'] and b'ERROR SUMMARY: 0 errors' in r.stderr
				r=run([exe,'--lifetime'],'native-lifetime-'+mode,0)
				assert b'FLOWSEM_LIFETIME_OK' in r.stdout
	finally:
		(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')


if __name__=='__main__':
	main()
