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
			outputs = []
			for mode in ('O0','O2'):
				r = run([a.build/('astra-flow-'+mode),'--flow',source],'existing-'+name+'-'+mode,0)
				o = decode(r.stdout)
				assert {18,20} <= {p['reason'] for p in o['proofs'] if p['proved']},(name,o['proofs'])
				outputs.append(r.stdout)
			assert outputs[0]==outputs[1]
		owned = ROOT/'tests/owned-state-6/prototypes/two-owner.astra'
		run([a.compiler,'--check',owned],'existing-owning-c0',0)
		for mode in ('O0','O2'):
			r = run([a.build/('astra-flow-'+mode),'--flow',owned],'existing-owning-'+mode,0)
			assert any(p['reason']==20 and p['proved'] for p in decode(r.stdout)['proofs'])
		result['existing'] = dict(nonnull=selected,owning=dict(path=str(owned),sha256=sha(owned)))
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
		old = json.loads((a.before/'product.json').read_text())
		old_exe = Path(old['identity']['argv'][-1])
		assert sha(old_exe)==old['sha256']
		before = run([old_exe,'--flow',*paths],'same-source-before',3)
		result['fixed_before'] = dict(sources={str(p):sha(p) for p in paths},status=3,deferrals=dict(Counter(decode(before.stdout)['deferrals'])),proofs=decode(before.stdout)['proofs'])
		for mode in ('O0','O2'):
			r = run([a.build/('astra-flow-'+mode),'--flow',*paths],'same-source-after-'+mode)
			o = decode(r.stdout)
			assert o['graphs'] and 'checked_error' not in o
			result['fixed_after_'+mode] = dict(status=o['status'],graphs=len(o['graphs']),events=len(o['events']),deferrals=dict(Counter(o['deferrals'])),errors=o['errors'],proofs=o['proofs'])
			# Current source is separately identified and never counted as whole-program safety.
		identity = json.loads((a.build/'astra-flow-O0.identity.json').read_text())['identity']
		current = [p for p in identity['sources'] if p.endswith('.astra') and '/tests/' not in p]
		outputs = []
		for mode in ('O0','O2'):
			r = run([a.build/('astra-flow-'+mode),'--flow',*current],'current-source-'+mode)
			o = decode(r.stdout)
			assert o['status']!=0 and o['graphs'] and 'checked_error' not in o
			outputs.append(r.stdout)
			result['current_'+mode] = dict(status=o['status'],graphs=len(o['graphs']),events=len(o['events']),deferrals=dict(Counter(o['deferrals'])),errors=o['errors'],proofs=o['proofs'])
		assert outputs[0]==outputs[1]
		result['current_sources'] = {p:sha(p) for p in current}
	finally:
		(a.runtime/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
		(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
	print('PASS source workload observations',a.runtime)


if __name__=='__main__':
	main()
