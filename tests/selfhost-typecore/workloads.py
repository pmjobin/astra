#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source-bound project, stress and depth observations for the checked consumer."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import resource
import subprocess
import time
from build import ROOT, sha
from run import decode


def main():
	p=argparse.ArgumentParser()
	for name in ('compiler','build','runtime'):p.add_argument('--'+name,type=Path,required=True)
	a=p.parse_args();resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	a.runtime.mkdir(parents=True,exist_ok=True);attempt=a.runtime/('workloads-'+str(time.time_ns()));attempt.mkdir();commands=[]
	def run(argv,name,expected=0):
		argv=list(map(str,argv));start=time.monotonic();r=subprocess.run(['/usr/bin/time','-v',*argv],capture_output=True,timeout=1200)
		(attempt/(name+'.stdout')).write_bytes(r.stdout);(attempt/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name,argv=argv,exit=r.returncode,seconds=time.monotonic()-start,stdout_sha256=hashlib.sha256(r.stdout).hexdigest()))
		(attempt/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
		assert r.returncode==expected,(name,r.returncode,r.stdout[-1000:],r.stderr[-1000:]);return r.stdout
	(attempt/'harness.json').write_text(json.dumps({str(Path(__file__)):sha(Path(__file__)),str(Path(__file__).with_name('run.py')):sha(Path(__file__).with_name('run.py'))},indent=2)+'\n')
	identities={mode:json.loads((a.build/('astra-types-'+mode+'.identity.json')).read_text()) for mode in ('O0','O2')}
	for mode,identity in identities.items():
		assert sha(a.build/('astra-types-'+mode))==identity['sha256']
		assert all(sha(path)==h for path,h in identity['identity']['sources'].items())
	inputs=[p for p in identities['O0']['identity']['sources'] if p.endswith('.astra')]
	assert inputs==[p for p in identities['O2']['identity']['sources'] if p.endswith('.astra')]
	(attempt/'inputs.json').write_text(json.dumps({p:sha(p) for p in inputs},indent=2)+'\n')
	oracle=json.loads(run([a.compiler,'--tooling-index',*inputs],'current-C0-index'))
	assert not oracle['diagnostics']
	run([a.compiler,'--dump-semantics',*inputs],'current-C0-dump')
	before=decode(run([a.build/'astra-bind-O0','--index',*inputs],'current-before-binding'))
	observations={};summaries={}
	for mode in ('O0','O2'):
		data=run([a.build/('astra-types-'+mode),'--types',*inputs],mode+'-current-source');observed=decode(data);observations[mode]=data
		assert 'error' not in observed
		assert len(before['references'])==len(observed['references'])
		closed=Counter();remaining=Counter()
		for old,new in zip(before['references'],observed['references']):
			assert old['span']==new['span']
			if old['state']==1:assert new['state']==1 and old['target']==new['target']
			elif old['state']==5:
				if new['state']==1:assert old['reason'] in (1,3,7) and new['target']>0;closed[old['reason']]+=1
				else:assert old==new;remaining[old['reason']]+=1
		deferrals=Counter(u['deferred'] for u in observed['uses'] if u['deferred'])
		samples={}
		for u in observed['uses']:
			if u['deferred'] and str(u['deferred']) not in samples:samples[str(u['deferred'])]=u
		by_span={d['span']:n for n,d in observed['declarations'].items()};matched=[];unprojected=Counter()
		for symbol in oracle['symbols']:
			if symbol['kind'] not in ('parameter','local','field'):continue
			span=(symbol['file'],symbol['start'],symbol['end'])
			if span not in by_span:unprojected['synthetic-or-materialized-source-identity']+=1;continue
			t=observed['symbols'][by_span[span]][0]
			if not t:unprojected['named-dependent-deferral']+=1;continue
			if observed['types'][t]['kind']>16:unprojected['structural-or-template-type-needs-instantiation-projection']+=1;continue
			name=observed['types'][t]['name'];detail=symbol['detail'];prefix=detail
			for qualifier in ('owned ','borrowed ','nonnull '):
				if prefix.startswith(qualifier):prefix=prefix[len(qualifier):]
			assert prefix.startswith(name+' '),(symbol,name)
			matched.append(dict(span=span,type=name,detail=detail))
		(attempt/(mode+'-current-common-types.json')).write_text(json.dumps(matched,indent=2)+'\n')
		summaries[mode]=dict(common_primitive_types=len(matched),unprojected=dict(unprojected),declarations=len(observed['declarations']),references=len(observed['references']),types=len(observed['types']),signatures=len(observed['signatures']),typed_uses=sum(bool(u['type']) for u in observed['uses']),deferrals=dict(deferrals),closed=dict(closed),remaining=dict(remaining),samples=samples)
	assert observations['O0']==observations['O2'],'current-source optimization divergence'
	(attempt/'current-summary.json').write_text(json.dumps(summaries,indent=2)+'\n')
	# Original sources remain distinct, and every ordinary stress expression is checked.
	paths=[]
	for n in range(16):
		path=attempt/f'stress-{n:02}.astra';path.write_text(f'namespace N{n};'+''.join(f'int f{i}(int x){{return x+{i};}}' for i in range(128)));paths.append(path)
	client=attempt/'stress-client.astra';client.write_text('int client(){return N15.f127(1);}');paths.append(client)
	stress={};
	for mode in ('O0','O2'):
		exe=a.build/('astra-types-'+mode)
		for name,selected in (('small',paths[:4]),('large',paths),('repeat',paths)):
			data=run([exe,'--types',*selected],mode+'-stress-'+name);d=decode(data);assert 'error' not in d and not any(u['deferred'] for u in d['uses'])
			if name=='large':stress[mode]=data
			if name=='repeat':assert data==stress[mode]
		for label in ('lifetime','stress'):
			args=['--lifetime'] if label=='lifetime' else ['--types',*paths]
			run(['valgrind','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=97',exe,*args],mode+'-memory-'+label)
	assert stress['O0']==stress['O2']
	for depth in (8,130):
		path=attempt/f'depth-{depth}.astra';path.write_text('struct Box<T>{T value;}int f('+'Box<'*depth+'int'+'>'*depth+' p){return 0;}')
		run([a.compiler,'--parse',path],f'depth-{depth}-C0-parse')
		run([a.compiler,'--tooling-index',path],f'depth-{depth}-C0',0)
		run([a.compiler,'--check',path],f'depth-{depth}-C0-full',0 if depth==8 else 1)
		for mode in ('O0','O2'):
			run([a.build/('astra-types-'+mode),'--types',path],f'depth-{depth}-'+mode,0 if depth==8 else 1)
	long=attempt/'long-literal.astra';long.write_text('int f(){return '+'0'*4096+'2147483647;}')
	run([a.compiler,'--tooling-index',long],'long-literal-C0')
	for mode in ('O0','O2'):run([a.build/('astra-types-'+mode),'--types',long],mode+'-long-literal')
	double=attempt/'double-release.astra';double.write_text('class Cell{init(){}}int main(){var value=new Cell();release value;release value;return 0;}')
	run([a.compiler,'--parse',double],'double-release-parse')
	diagnostic=json.loads(run([a.compiler,'--tooling-index',double],'double-release-C0'))
	assert not diagnostic['diagnostics']
	run([a.compiler,'--check',double],'double-release-full-pipeline',1)
	for mode in ('O0','O2'):
		exe=attempt/('double-release-'+mode)
		run([a.compiler,'-'+mode,double,'-o',exe],mode+'-double-release-build',1)
		assert not exe.exists()
		assert b'already been released' in (attempt/(mode+'-double-release-build.stderr')).read_bytes()
	(attempt/'result.json').write_text(json.dumps(dict(status='PASS',scope='Current mixed project source, exact before/after Binder edges, scalar stress, constructor depth, long spelling, C0 ownership guard; no cold-cache or global speed claim',commands=len(commands),depth_observation='C0 tooling/dump may expose depth 130 before materialization; C0 full --check and the candidate both enforce the 128 constructor-depth limit at their respective phases'),indent=2)+'\n')
	print(attempt)


if __name__=='__main__':main()
