#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real project observations plus admitted multisource/depth/limit workloads."""
import argparse
from collections import Counter
import json
import os
from pathlib import Path
import re
import subprocess
import time
from build import ROOT,sha
from run import decode


def main():
	p=argparse.ArgumentParser()
	p.add_argument('--compiler',type=Path,required=True)
	p.add_argument('--build',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	p.add_argument('--mode',action='append')
	a=p.parse_args()
	modes=a.mode or ('O0','O2')
	a.runtime.mkdir(parents=True,exist_ok=False)
	rows=[]
	result={'profiles':list(modes)}
	def run(argv,name,expected=None):
		start=time.monotonic()
		r=subprocess.run(['/usr/bin/time','-v','-o',str(a.runtime/(name+'.time.log')),*map(str,argv)],cwd=ROOT,capture_output=True,env=dict(os.environ,CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,seconds=time.monotonic()-start,peak_rss_kib=int(re.search(r'Maximum resident set size \(kbytes\): (\d+)',(a.runtime/(name+'.time.log')).read_text())[1])))
		if expected is not None:
			assert r.returncode==expected,(name,r.stderr.decode()[-3000:])
		return r
	try:
		# Each routine transfers both directions within a real zero-or-more loop.
		paths=[]
		for unit in range(8):
			path=a.runtime/('batch-'+str(unit)+'.astra')
			text='namespace Batch'+str(unit)+';void observe(int[] value){}\n'
			for number in range(32):
				text+='owned int[] stage_'+str(number)+'(owned int[] input,int rounds){for(int i=0;i<rounds;i=i+1){var next=move input;observe(next);input=move next;}return move input;}\n'
			path.write_text(text)
			paths.append(path)
		client=a.runtime/'client.astra'
		client.write_text('int main(){var current=new int[4];var next=Batch0.stage_0(move current,3);current=move next;return 0;}\n')
		paths.append(client)
		run([a.compiler,'--check',*paths],'multisource-c0',0)
		observations=[]
		for mode in modes:
			exe=a.build/('astra-flow-'+mode)
			r=run([exe,'--flow',*paths],'multisource-'+mode,0)
			observations.append(r.stdout)
			o=decode(r.stdout)
			assert o['status']==0 and len(o['graphs'])==265 and sum(e['op']==11 for e in o['events'].values())==256
			assert sum(e['op'] in (2,4,5,6,13) for e in o['events'].values())>=1000
			result['admitted']=dict(functions=len(o['graphs']),events=len(o['events']),loans=len(o['loans']),proofs=sum(p[2] for p in o['proofs']))
			r=run(['valgrind','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe,'--flow',*paths],'memory-multisource-'+mode,0)
			assert b'ERROR SUMMARY: 0 errors' in r.stderr
		if len(observations)==2:
			assert observations[0]==observations[1]
			# A short source edit loop reuses the exact executable but never a test result.
		edit=a.runtime/'edit.astra'
		edit.write_text('void f(owned int[] x){release x;}')
		for mode in modes:
			exe=a.build/('astra-flow-'+mode)
			run([exe,'--flow',edit],'edit-before-'+mode,0)
		edit.write_text('void f(owned int[] x){release x;release x;}')
		run([a.compiler,'--check',edit],'edit-c0-negative',1)
		for mode in modes:
			exe=a.build/('astra-flow-'+mode)
			r=run([exe,'--flow',edit],'edit-negative-'+mode,1)
			assert decode(r.stdout)['errors'][0][0]=='DOUBLE_RELEASE'
		edit.write_text('void f(owned int[] x){release x;x=new int[2];release x;}')
		for mode in modes:
			run([a.build/('astra-flow-'+mode),'--flow',edit],'edit-repaired-'+mode,0)
		for depth in (96,200):
			path=a.runtime/('deep-'+str(depth)+'.astra')
			path.write_text('void f(owned int[] x){'+'{ '*depth+'int i=0;'+'} '*depth+'release x;}')
			run([a.compiler,'--parse',path],'deep-parse-'+str(depth),0)
			for mode in modes:
				exe=a.build/('astra-flow-'+mode)
				r=run([exe,'--flow',path],'deep-'+str(depth)+'-'+mode,0 if depth==96 else 1)
				if depth==200:
					assert decode(r.stdout)['errors'][0][0]=='FLOW_RESOURCE_EXHAUSTED'
				r=run(['valgrind','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe,'--flow',path],'memory-deep-'+str(depth)+'-'+mode,0 if depth==96 else 1)
				assert b'ERROR SUMMARY: 0 errors' in r.stderr
				# Whole current source is a mixed-domain observation, never a blanket PASS.
		identity=json.loads((a.build/'astra-flow-O0.identity.json').read_text())['identity']
		project=[p for p in identity['sources'] if p.endswith('.astra') and '/tests/' not in p]
		project_outputs=[]
		for mode in modes:
			r=run([a.build/('astra-flow-'+mode),'--flow',*project],'current-source-'+mode)
			o=decode(r.stdout)
			project_outputs.append(r.stdout)
			assert 'checked_error' not in o and o['graphs'] and o['events'],'current project failed before flow construction'
			assert o['status']==3 and o['deferrals'],'mixed-domain project must remain explicitly deferred'
			result['current_source']=dict(status=o['status'],graphs=len(o['graphs']),events=len(o['events']),loans=len(o['loans']),deferrals=dict(Counter(o['deferrals'])),errors=o['errors'][:10],checked_error=o.get('checked_error'),proved_reason19=sum(p[2] for p in o['proofs'] if p[1]==19))
		if len(project_outputs)==2:
			assert project_outputs[0]==project_outputs[1]
		result['sources']={str(p):sha(p) for p in paths}
		result['products']={m:sha(a.build/('astra-flow-'+m)) for m in modes}
	finally:
		(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
		(a.runtime/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
	print('PASS workloads',result)


if __name__=='__main__':
	main()
