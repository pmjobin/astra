#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""One final qualification/profile against a real combined current compiler."""
import argparse
import json
import os
from pathlib import Path
import sys
import time
from state import ROOT, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode',choices=('O0','O2'),required=True); p.add_argument('--version',required=True); p.add_argument('--component',type=Path,required=True); p.add_argument('--resume',action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('recover_consolidated_paths',ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('consolidated-'+a.version+'-'+a.mode); leaf.mkdir(exist_ok=a.resume); component = a.component.resolve(); identity = read(component.with_suffix('.identity.json')); assert sha(component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode and all(sha(path) == expected for group in ('sources','tools') for path,expected in identity['identity'][group].items())
	commands = read(leaf/'commands.json') if a.resume else []; environment = dict(os.environ,CCACHE_DISABLE='1'); environment.pop('LD_PRELOAD',None); environment.pop('VALGRIND_OPTS',None)
	jobs = [('recover-regression',a.version,[]),('recover-qualify',a.version+'scalar',['--expanded']),('recover-record-qualify',a.version+'record',[]),('recover-owned-qualify',a.version+'owned',[]),('recover-error-owned-qualify',a.version+'errors',[]),('recover-loop-qualify',a.version+'loops',[]),('recover-adversarial',a.version,[]),('recover-owner-adversarial',a.version,[]),('recover-loop-adversarial',a.version,[]),('recover-class-policy',a.version,[]),('recover-null-guard',a.version,[]),('recover-success-probe',a.version,[]),('recover-abi-limit',a.version+a.mode,[]),('recover-original',a.version,['--provider-build',str(component.parent)]),('recover-frontier',a.version,[])]
	versions = {}
	for name,version,extra in jobs:
		previous = [row for row in commands if row['name'] == name]; prior = previous[-1] if previous else None
		if prior is not None:
			label = prior.get('label',name); assert prior['component_sha256'] == sha(component) and sha(leaf/(label+'.stdout')) == prior['stdout_sha256'] and sha(leaf/(label+'.stderr')) == prior['stderr_sha256']
			if prior['exit'] == 0:
				versions[name] = prior['argv'][prior['argv'].index('--version')+1]; print(a.mode,name,'previous completed job preserved',flush=True); continue
			version += 'retry'+str(len(previous))
		label = name if not previous else name+'-retry'+str(len(previous)); versions[name] = version
		argv = [sys.executable,'-B',ROOT/('tests/selfhost-effects/'+name+'.py'),'--component',component,'--version',version]
		if name != 'recover-abi-limit': argv += ['--mode',a.mode]
		argv += extra; start = time.monotonic(); r = bounded_run(['/usr/bin/time','-v','-o',leaf/(label+'.time'),*argv],cwd=ROOT,env=environment,capture_output=True,timeout=2400); (leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr); command = dict(name=name,label=label,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),component_sha256=sha(component),stdout_sha256=sha(leaf/(label+'.stdout')),stderr_sha256=sha(leaf/(label+'.stderr'))); commands.append(command); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); assert r.returncode == 0,(name,r.stdout[-2500:],r.stderr[-3500:]); print(a.mode,name,'qualification recipe completed; see its actual status/deferrals',flush=True)
	def location(prefix,job): return prefix+'-'+versions[job]+'-'+a.mode
	configuration = dict(component=str(component),regression=location('regression','recover-regression'),native_results=[location('early',job) for job in ('recover-qualify','recover-record-qualify','recover-owned-qualify','recover-error-owned-qualify','recover-loop-qualify')],adversarial=[location(prefix,job) for prefix,job in [('adversarial','recover-adversarial'),('owner-adversarial','recover-owner-adversarial'),('loop-adversarial','recover-loop-adversarial')]],original=location('original','recover-original'),frontier=location('frontier','recover-frontier'),class_policy=location('class-policy','recover-class-policy'),null_guard=location('null-guard','recover-null-guard'),ABI_success_probe=location('success-cell','recover-success-probe'),ABI_limit='abi-limit-'+versions['recover-abi-limit'])
	(leaf/'result.json').write_text(json.dumps(dict(status='CONSOLIDATED_RECIPES_COMPLETED',profile=a.mode,component_sha256=sha(component),profile_configuration=configuration,limitation='This indicates completed recipes, not an overall milestone PASS. Read the original-source/frontier results and final gate audit.'),indent=2)+'\n'); print(a.mode,'consolidated results retained',flush=True)


if __name__ == '__main__':
	main()
