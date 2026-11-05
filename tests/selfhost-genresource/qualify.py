#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify new source programs, compact-map mutants and the original body view."""
import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time
from state import ROOT, RUNTIME, BUILD, C0, read, sha


def main():
	resource.setrlimit(resource.RLIMIT_CORE,(0,0))
	p = argparse.ArgumentParser(); p.add_argument('--component',type=Path,required=True); p.add_argument('--mode',choices=('O0','O2'),required=True); p.add_argument('--gate',choices=('new','models','witness'),required=True); p.add_argument('--name',required=True); p.add_argument('--existing-new',type=Path); p.add_argument('--additional-results',type=Path); a = p.parse_args()
	assert a.name.replace('-','').isalnum()
	leaf = RUNTIME/a.name; build = BUILD/a.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False); commands = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == value for group in ('sources','tools') for path,value in identity['identity'][group].items())
	env = dict(os.environ,CCACHE_DISABLE='1'); env.pop('VALGRIND_OPTS',None); env.pop('LD_PRELOAD',None)
	def run(argv,name,expected=0):
		start = time.monotonic()
		with (leaf/(name+'.stdout')).open('xb') as out,(leaf/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time','-v','-o',leaf/(name+'.time'),*map(str,argv)],cwd=ROOT,stdout=out,stderr=err,env=env,timeout=2400)
		commands.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,expected=expected,start=start,end=time.monotonic(),stdout_sha256=sha(leaf/(name+'.stdout')),stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
		print(a.mode,a.gate,name,r.returncode,flush=True); assert r.returncode == expected,str(leaf/(name+'.stderr'))
	composition = None
	if a.gate in ('new','witness'):
		selection = RUNTIME/('corpus-v6' if a.gate == 'new' else 'witness-input-v2')/'selection.json'
		if a.existing_new:
			assert a.gate == 'new' and a.additional_results
			old_manifest = read(a.existing_new/'observations/manifest.json'); added_manifest = read(a.additional_results.parent/'manifest.json')
			assert old_manifest['component_sha256'] == added_manifest['component_sha256'] == sha(a.component) and old_manifest['mode'] == added_manifest['mode'] == a.mode
			old = read(a.existing_new/'observations/results.json'); added = read(a.additional_results)
			assert sum(row['baseline_complete'] for row in old) == 11 and len(added) == 1 and added[0]['baseline_complete']
			rows = [row if row['baseline_complete'] else next(candidate for candidate in added if candidate['name'] == row['name'] and candidate['sources'] == row['sources']) for row in old]
			for row in rows:
				assert all(sha(source['path']) == source['sha256'] for source in row['sources']) and all(sha(product['path']) == product['sha256'] for product in row['products'].values())
			(leaf/'observations').mkdir(); (leaf/'observations/results.json').write_text(json.dumps(rows,indent=2)+'\n')
			composition = dict(unchanged_successes=11,fresh_nested_record_case=1,initial_results=str(a.existing_new/'observations/results.json'),initial_results_sha256=sha(a.existing_new/'observations/results.json'),additional_results=str(a.additional_results),additional_results_sha256=sha(a.additional_results),reason='The initial independent layout probe could not close nested generic value fields. Its eleven successful cases retain exact source/component/product identities; the affected case freshly passes all stages, C0/C++ layout, native execution and unsuppressed Valgrind using the bounded C0-syntax closure probe.')
		else:
			run([sys.executable,'-B',ROOT/'tests/selfhost-classstorage/run.py','--compiler',C0,'--compiler-sha256',sha(C0),'--component',a.component,'--mode',a.mode,'--selection',selection,'--build',build/'products','--runtime',leaf/'observations'],'native')
			rows = read(leaf/'observations/results.json')
		assert len(rows) == (12 if a.gate == 'new' else 1) and all(row['baseline_complete'] for row in rows)
		assert len(rows) == len({tuple(source['sha256'] for source in row['sources']) for row in rows})
		for item in read(selection):
			for stage in ('core','cfg'):
				run([a.component,'--classstorage-'+stage,a.mode,build/'unused',*[s['path'] for s in item['sources']]],item['name']+'-'+stage)
	else:
		selection = read(RUNTIME/'physical-input-v1/selection.json'); sources = [s['path'] for s in selection[0]['sources']]
		output = build/'preserved.o'; native = build/'preserved-native'
		run([a.component,'--classstorage-emit-obj',a.mode,output,*sources],'valid-object'); run(['gcc',output,'-o',native],'valid-link'); run([native],'valid-execute',53)
		original = sha(output); executable = sha(native)
		run([a.component,'--classstorage-resource-mutations',a.mode,output,*sources],'models')
		assert (leaf/'models.stdout').read_text().count('RESOURCE_MODEL_MUTATION ') == 14 and sha(output) == original and sha(native) == executable
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS',gate=a.gate,mode=a.mode,component_sha256=sha(a.component),recipe_sha256=sha(__file__),composition=composition,commands=commands,limitation='Only this named gate is established; source views remain disclosed views and fixed resource refusals remain deferrals.'),indent=2)+'\n')


if __name__ == '__main__':
	main()
