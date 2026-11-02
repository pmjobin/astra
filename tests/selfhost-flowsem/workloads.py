#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Existing project families, unchanged source inventory, scale and cost ledger."""
import argparse
import ast
from collections import Counter
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import time
from build import ROOT, sha
from run import decode


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--before', type=Path, required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False)
	rows, result = [], {}
	old = json.loads((a.before/'product.json').read_text())
	old_exe = Path(old['identity']['argv'][-1])
	assert sha(old_exe)==old['sha256']
	def run(argv, name, expected=None):
		argv = list(map(str,argv))
		start = time.monotonic()
		time_log = a.runtime/(name+'.time.log')
		r = subprocess.run(['/usr/bin/time','-v','-o',str(time_log),*argv],cwd=ROOT,capture_output=True,env=dict(os.environ,CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(name=name,argv=argv,exit=r.returncode,seconds=time.monotonic()-start,peak_rss_kib=int(re.search(r'Maximum resident set size \(kbytes\): (\d+)',time_log.read_text())[1])))
		(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
		if expected is not None:
			assert r.returncode==expected,(name,r.stderr.decode()[-3000:])
		return r
	try:
		# These sources are the existing registered test's actual authored data.
		path = ROOT/'tests/language-usability-7/nonnull-check.py'
		spec = importlib.util.spec_from_file_location('nonnull_cases',path)
		module = importlib.util.module_from_spec(spec)
		spec.loader.exec_module(module)
		tree = ast.parse(path.read_text())
		value = next(node.value for node in ast.walk(tree) if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='positive' for t in node.targets))
		cases = eval(compile(ast.Expression(value),str(path),'eval'),{'PRELUDE':module.PRELUDE})
		selected = {}
		for name in ('guard','short-and','short-or','loop','branch-join'):
			source = a.runtime/('existing-'+name+'.astra')
			source.write_text(cases[name]+'\n')
			run([a.compiler,'--check',source],'existing-c0-'+name,0)
			selected[name] = dict(origin=str(path),origin_sha256=sha(path),source=str(source),sha256=sha(source))
			before = decode(run([old_exe,'--flow',source],'existing-before-'+name,3).stdout)
			outputs = []
			for mode in ('O0','O2'):
				r = run([a.build/('astra-flow-'+mode),'--flow',source],'existing-'+name+'-'+mode,0)
				o = decode(r.stdout)
				assert {18,20} <= {p['reason'] for p in o['proofs'] if p['proved']},(name,o['proofs'])
				outputs.append(r.stdout)
			assert outputs[0]==outputs[1]
			selected[name]['before'] = before['proofs']
			selected[name]['after'] = o['proofs']
			assert any(p['reason']==18 and not p['proved'] for p in before['proofs'])
		owned = ROOT/'tests/owned-state-6/prototypes/two-owner.astra'
		run([a.compiler,'--check',owned],'existing-owning-c0',0)
		before = decode(run([old_exe,'--flow',owned],'existing-owning-before',3).stdout)
		for mode in ('O0','O2'):
			r = run([a.build/('astra-flow-'+mode),'--flow',owned],'existing-owning-'+mode,0)
			assert any(p['reason']==20 and p['proved'] for p in decode(r.stdout)['proofs'])
		result['existing'] = dict(nonnull=selected,owning=dict(path=str(owned),sha256=sha(owned),before=before['proofs'],after=decode(r.stdout)['proofs']))
		# One bounded multisource program exercises both proof families at scale.
		paths = []
		for batch in range(4):
			source = a.runtime/('scale-'+str(batch)+'.astra')
			text = 'namespace Scale'+str(batch)+';class C{init(){}}void use(nonnull C p){}struct Packet{owned int[] data;int tag;}\n'
			for number in range(16):
				text += 'int classify_'+str(number)+'(C p,int rounds){int i=0;int total=0;while(i<rounds){if(p!=null){use(p);total=total+1;}i=i+1;}return total;}\n'
				text += 'int packet_'+str(number)+'(int size){var data=new int[size];Packet p={data=move data,tag=size};var q=move p;return q.tag;}\n'
			source.write_text(text)
			paths.append(source)
		client = a.runtime/'scale-client.astra'
		client.write_text('int main(){var p=new Scale0.C();if(Scale0.classify_0(p,0)!=0||Scale0.classify_0(p,1)!=1||Scale0.classify_0(p,5)!=5||Scale0.classify_0(null,5)!=0||Scale0.packet_0(3)!=3||Scale0.packet_1(0)!=0){return 1;}return 0;}\n')
		paths.append(client)
		run([a.compiler,'--check',*paths],'scale-c0',0)
		outputs = []
		for mode in ('O0','O2'):
			exe = a.build/('astra-flow-'+mode)
			r = run([exe,'--flow',*paths],'scale-'+mode,0)
			o = decode(r.stdout)
			assert len(o['graphs'])==137 and {18,19,20}<={p['reason'] for p in o['proofs'] if p['proved']}
			outputs.append(r.stdout)
			result['scale_'+mode] = dict(graphs=len(o['graphs']),events=len(o['events']),fields=len(o['fields']),proofs=dict(Counter(p['reason'] for p in o['proofs'] if p['proved'])))
			r = run(['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe,'--flow',*paths],'scale-memory-'+mode,0)
			assert b'ERROR SUMMARY: 0 errors' in r.stderr and not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]',r.stderr)
			program = a.build/('scale-program-'+mode)
			run([a.compiler,'-'+mode,*paths,'-o',program],'scale-compile-'+mode,0)
			run([program],'scale-execute-'+mode,0)
			r = run(['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',program],'scale-program-memory-'+mode,0)
			assert b'ERROR SUMMARY: 0 errors' in r.stderr and not re.search(rb'(?:definitely|indirectly|possibly) lost: [1-9]',r.stderr)
		assert outputs[0]==outputs[1]
		result['scale_sources'] = {str(p):sha(p) for p in paths}
		# Reconstruct the original Git-pinned workload into task-owned runtime;
		# original and candidate observations use exactly these same source bytes.
		inventory = json.loads((a.before/'compiler-source-inputs.json').read_text())
		fixed = a.runtime/'baseline-source'
		fixed.mkdir()
		paths = []
		for original,digest in inventory.items():
			rel = Path(original).relative_to(ROOT)
			source = fixed/rel
			source.parent.mkdir(parents=True,exist_ok=True)
			data = subprocess.check_output(['git','-C',str(ROOT),'show','da7110d4445c48d7e3ad0ede74f33511dbe5dd81:'+str(rel)])
			assert hashlib.sha256(data).hexdigest()==digest
			source.write_bytes(data)
			paths.append(source)
		before = run([old_exe,'--flow',*paths],'same-source-before',3)
		o = decode(before.stdout)
		counts = (len(o['graphs']),len(o['events']),sum(line.startswith(b'L ') for line in before.stdout.splitlines()))
		assert counts==(1460,81304,1361),counts
		result['fixed_before'] = dict(sources={str(p):sha(p) for p in paths},status=3,graphs=counts[0],events=counts[1],loans=counts[2],deferrals=dict(Counter(o['deferrals'])),proofs=o['proofs'])
		outputs = []
		for mode in ('O0','O2'):
			r = run([a.build/('astra-flow-'+mode),'--flow',*paths],'same-source-after-'+mode)
			o = decode(r.stdout)
			assert r.returncode==o['status']==3 and o['graphs'] and not o['errors'] and 'checked_error' not in o
			outputs.append(r.stdout)
			result['fixed_after_'+mode] = dict(status=o['status'],graphs=len(o['graphs']),events=len(o['events']),loans=sum(line.startswith(b'L ') for line in r.stdout.splitlines()),deferrals=dict(Counter(o['deferrals'])),errors=o['errors'],proofs=o['proofs'])
		assert outputs[0]==outputs[1]
			# Current source is separately identified and never counted as whole-program safety.
		identity = json.loads((a.build/'astra-flow-O0.identity.json').read_text())['identity']
		current = [p for p in identity['sources'] if p.endswith('.astra') and '/tests/' not in p]
		outputs = []
		for mode in ('O0','O2'):
			r = run([a.build/('astra-flow-'+mode),'--flow',*current],'current-source-'+mode)
			o = decode(r.stdout)
			assert r.returncode==o['status']==3 and o['graphs'] and not o['errors'] and 'checked_error' not in o
			outputs.append(r.stdout)
			result['current_'+mode] = dict(status=o['status'],graphs=len(o['graphs']),events=len(o['events']),loans=sum(line.startswith(b'L ') for line in r.stdout.splitlines()),deferrals=dict(Counter(o['deferrals'])),errors=o['errors'],proofs=o['proofs'])
		assert outputs[0]==outputs[1]
		result['current_sources'] = {p:sha(p) for p in current}
	finally:
		(a.runtime/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
		(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
	print('PASS source workload observations',a.runtime)


if __name__=='__main__':
	main()
