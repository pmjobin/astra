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
	for name,version,extra in jobs:
		prior = next((row for row in commands if row['name'] == name),None)
		if prior is not None:
			assert prior['exit'] == 0 and prior['component_sha256'] == sha(component) and sha(leaf/(name+'.stdout')) == prior['stdout_sha256'] and sha(leaf/(name+'.stderr')) == prior['stderr_sha256']; print(a.mode,name,'previous completed job preserved',flush=True); continue
		argv = [sys.executable,'-B',ROOT/('tests/selfhost-effects/'+name+'.py'),'--component',component,'--version',version]
		if name != 'recover-abi-limit': argv += ['--mode',a.mode]
		argv += extra; start = time.monotonic(); r = bounded_run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*argv],cwd=ROOT,env=environment,capture_output=True,timeout=2400); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); command = dict(name=name,argv=list(map(str,argv)),exit=r.returncode,start=start,end=time.monotonic(),component_sha256=sha(component),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr'))); commands.append(command); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); assert r.returncode == 0,(name,r.stdout[-2500:],r.stderr[-3500:]); print(a.mode,name,'qualification recipe completed; see its actual status/deferrals',flush=True)
	configuration = dict(component=str(component),regression='regression-'+a.version+'-'+a.mode,native_results=['early-'+a.version+suffix+'-'+a.mode for suffix in ('scalar','record','owned','errors','loops')],adversarial=[prefix+'-'+a.version+'-'+a.mode for prefix in ('adversarial','owner-adversarial','loop-adversarial')],original='original-'+a.version+'-'+a.mode,frontier='frontier-'+a.version+'-'+a.mode,class_policy='class-policy-'+a.version+'-'+a.mode,null_guard='null-guard-'+a.version+'-'+a.mode,ABI_success_probe='success-cell-'+a.version+'-'+a.mode,ABI_limit='abi-limit-'+a.version+a.mode)
	(leaf/'result.json').write_text(json.dumps(dict(status='CONSOLIDATED_RECIPES_COMPLETED',profile=a.mode,component_sha256=sha(component),profile_configuration=configuration,limitation='This indicates completed recipes, not an overall milestone PASS. Read the original-source/frontier results and final gate audit.'),indent=2)+'\n'); print(a.mode,'consolidated results retained',flush=True)


if __name__ == '__main__':
	main()
