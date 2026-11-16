#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay established native suites and unchanged source-consumer products."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
from threading import Lock

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write


def replay_bound_qualification(a):
	assert a.qualification_sha256 and sha(a.qualification)==a.qualification_sha256
	q = json.loads(a.qualification.read_text())
	for key in ('products_manifest','toolchain','link','regression_plans'): assert sha(q[key]['path'])==q[key]['sha256']
	plans = json.loads(Path(q['regression_plans']['path']).read_text())
	expected = {mode+'-'+name for mode in ('O0','O2') for name in ('named','match','range','format','collection','ownership','intrinsic','C-client','physical-owner','physical-range','physical-enum','source-owner-memory','docs-focused','api-preview')}|{'docs-native'}
	assert len(plans)==29 and {row['label'] for row in plans}==expected
	b = output_path(a.build,WORK/'build'); r = output_path(a.runtime,WORK/'runtime')
	b.mkdir(parents=True,exist_ok=False); r.mkdir(parents=True,exist_ok=False)
	(r/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	start = datetime.datetime.now(datetime.timezone.utc).isoformat()
	t = json.loads(Path(q['toolchain']['path']).read_text()); assert all(sha(p)==h for p,h in t['tools'].items())
	env = dict(os.environ,PYTHONDONTWRITEBYTECODE='1',CCACHE_DISABLE='1'); env.update({k:v for k,v in t['environment'].items() if v is not None}); env.pop('LD_PRELOAD',None); env.pop('VALGRIND_OPTS',None)
	schema_path = WORK/'runtime/api-docs28a1-schema-test-environment/result.json'; schema = json.loads(schema_path.read_text())
	assert schema['status']=='ACTUAL_PINNED_PYTHON_SCHEMA_POSITIVE_AND_NEGATIVE_PASS' and all(sha(p)==h for p,h in schema['loaded_dependency_bytes'].items())
	env['PYTHONPATH'] = schema['PYTHONPATH']
	debugger = r/'tool-bin/gdb'; debugger.parent.mkdir(); debugger.write_bytes((ROOT/'tests/api-docs/gdb-host.py').read_bytes()); debugger.chmod(0o755)
	env['PATH'] = str(debugger.parent)+os.pathsep+env['PATH']
	assert subprocess.check_output(['llvm-config','--version'],env=env).strip()==b'23.1.4'
	assert all(sha(row['path'])==row['sha256'] for row in q['source_consumers'].values())
	for plan in plans:
		for flag,parent in (('--build',b),('--runtime',r)):
			if flag in plan['argv']: plan['argv'][plan['argv'].index(flag)+1] = str(parent/plan['label'])
	if a.docs_only: plans = [row for row in plans if row['label'].endswith(('-docs-focused','-api-preview'))]
	write(r/'plans.json',plans)
	results = []; lock = Lock()
	def job(plan):
		v = execute(plan['argv'],r/(plan['label']+'-controller'),expected=plan.get('expected',0),timeout=2400,env=env)
		row = dict(label=plan['label'],argv=plan['argv'],result=v)
		with lock:
			results.append(row); write(r/'commands.json',results)
		print(plan['label'],v['status'],round(v['seconds'],2),flush=True)
		return row
	with ThreadPoolExecutor(max_workers=2) as pool: list(pool.map(job,plans))
	passed = all(row['result']['status']=='EXPECTED_OUTCOME' for row in results)
	write(r/'result.json',dict(status=('CURRENT_BOOK_DOC_SCHEMA_PREVIEW_PASS' if a.docs_only else 'CURRENT_BOOK_NONREGRESSION_PASS') if passed else 'CURRENT_BOOK_NONREGRESSION_FAILURE',start_UTC=start,completed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),qualification_sha256=a.qualification_sha256,plans_sha256=sha(r/'plans.json'),commands_sha256=sha(r/'commands.json'),suites=results,scope='Only the explicitly hashed predecessor plans, rerouted to fresh external outputs. Exact unchanged products and historical C0 oracle inputs retain their original identities. Current raw/memory/mutation outcomes require the independent final audit; no historical reclassification or safety waiver.'))
	assert passed


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--build',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	p.add_argument('--docs-only',action='store_true',help='Retry only schema/extraction lanes after an environment correction')
	p.add_argument('--qualification',type=Path,help='Replay the exact hashed plans bound by an authenticated 28-A2 qualification')
	p.add_argument('--qualification-sha256')
	a = p.parse_args()
	if a.qualification:
		replay_bound_qualification(a)
		return
	build = output_path(a.build,WORK/'build'); runtime = output_path(a.runtime,WORK/'runtime')
	build.mkdir(parents=True,exist_ok=False); runtime.mkdir(parents=True,exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	start = datetime.datetime.now(datetime.timezone.utc).isoformat()
	input_root = WORK/'runtime/native-current/input'
	qualification_path = input_root/'reference/report28a1/evidence/QUALIFICATION.json'
	qualification = json.loads(qualification_path.read_text())
	assert sha(qualification_path) == '4877c41a315b5c912745bcf6eb44728dce8fd9b4105b03ad4211b263ac2bf05d'
	products_path = Path(qualification['products_manifest']['path'])
	assert sha(products_path) == qualification['products_manifest']['sha256']
	products = json.loads(products_path.read_text())['products']
	toolchain_path = WORK/'runtime/selfhost27c-dev21/build-identity.json'
	toolchain = json.loads(toolchain_path.read_text())
	assert all(sha(path) == h for path,h in toolchain['tools'].items())
	env = dict(os.environ,PYTHONDONTWRITEBYTECODE='1',CCACHE_DISABLE='1')
	env.update({k:v for k,v in toolchain['environment'].items() if v is not None})
	env.pop('LD_PRELOAD',None); env.pop('VALGRIND_OPTS',None)
	schema_path = WORK/'runtime/api-docs28a1-schema-test-environment/result.json'
	schema = json.loads(schema_path.read_text())
	assert schema['status']=='ACTUAL_PINNED_PYTHON_SCHEMA_POSITIVE_AND_NEGATIVE_PASS'
	assert all(sha(path)==digest for path,digest in schema['loaded_dependency_bytes'].items())
	env['PYTHONPATH'] = schema['PYTHONPATH']
	write(runtime/'schema-environment.json',dict(receipt_sha256=sha(schema_path),dependencies=schema['loaded_dependency_bytes'],PYTHONPATH=env['PYTHONPATH'],scope='Existing read-only schema dependencies; no package installation or native-toolchain change.'))
	assert subprocess.check_output(['llvm-config','--version'],env=env).strip() == b'23.1.4'
	debugger = runtime/'tool-bin/gdb'; debugger.parent.mkdir()
	debugger.write_bytes((ROOT/'tests/api-docs/gdb-host.py').read_bytes()); debugger.chmod(0o755)
	env['PATH'] = str(debugger.parent)+os.pathsep+env['PATH']
	plans = []
	for mode,product in products.items():
		for image in (product,product['native'],product['doc']): assert sha(image['path']) == image['sha256']
		bound = qualification['receipts'][mode+'-consolidated']
		assert sha(bound['path']) == bound['sha256']
		old = Path(bound['path']).parent
		assert sha(old/'plans.json') == json.loads(Path(bound['path']).read_text())['plans_sha256']
		for row in json.loads((old/'plans.json').read_text()):
			assert sha(row['recipe']) == row['recipe_sha256']
			if row['label'].endswith('-source-owner'): continue
			plans.append(dict(label=row['label'],argv=['python3','-B',row['recipe'],*row['options'],'--build',str(build/row['label']),'--runtime',str(runtime/row['label'])]))
			# No source-consumer rebuild is needed: reauthenticate every embedded source,
			# recipe, provider and tool before executing both retained O0/O2 products.
	owner = qualification['receipts']['source-owner']; assert sha(owner['path']) == owner['sha256']
	owner_path = Path(owner['path']); owner_result = json.loads(owner_path.read_text())
	identity_path = owner_path.with_name('identity.json'); assert sha(identity_path) == owner_result['identity_sha256']
	identity = json.loads(identity_path.read_text())
	for group in ('sources','actual_sources','providers','tools'):
		assert all(sha(path) == value for path,value in identity[group].items()),group
	write(runtime/'source-consumer-reuse.json',dict(bound_qualification_sha256=sha(qualification_path),receipt_sha256=sha(owner_path),identity=identity,reason='Compiler/library/consumer source, provider and tool bytes unchanged; execute retained products freshly, do not relabel their historical build revision.'))
	for mode,product in owner_result['products'].items():
		assert sha(product['path']) == product['sha256']
		plans.append(dict(label=mode+'-source-owner-memory',argv=['valgrind','--default-suppressions=no','--error-exitcode=99','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all',product['path']],expected=42,memory=True))
	plans.append(dict(label='docs-native',argv=['python3','-B',str(ROOT/'tests/api-docs/native.py'),'--products',str(products_path),'--toolchain',str(toolchain_path),'--build',str(build/'docs-native'),'--runtime',str(runtime/'docs-native')]))
	for mode,product in products.items():
		identity = WORK/('runtime/api-docs28a1-bundle-'+mode+'/docs-build-identity.json')
		plans.append(dict(label=mode+'-docs-focused',argv=['python3','-B',str(ROOT/'tests/api-docs/run.py'),'--compiler',product['path'],'--compiler-sha256',product['sha256'],'--toolchain',str(toolchain_path),'--build-identity',str(identity),'--runtime',str(runtime/(mode+'-docs-focused'))]))
		plans.append(dict(label=mode+'-api-preview',argv=['python3','-B',str(ROOT/'tools/docs/preview.py'),'--products',str(products_path),'--identity',str(identity),'--toolchain',str(toolchain_path),'--mode',mode,'--build',str(build/(mode+'-api-preview')),'--runtime',str(runtime/(mode+'-api-preview'))]))
	if a.docs_only: plans = [row for row in plans if row['label'].endswith(('-docs-focused','-api-preview'))]
	write(runtime/'plans.json',plans)
	def job(plan):
		label = plan['label']
		result = execute(plan['argv'],runtime/(label+'-controller'),expected=plan.get('expected',0),timeout=1800,env=env)
		if plan.get('memory'):
			assert all(marker in (runtime/(label+'-controller/stderr')).read_bytes() for marker in (b'ERROR SUMMARY: 0 errors',b'in use at exit: 0 bytes in 0 blocks',b'(suppressed: 0 from 0)'))
		print(label,result['status'],round(result['seconds'],2),flush=True)
		return dict(label=label,result=result,receipt_sha256=sha(runtime/label/'result.json') if (runtime/label/'result.json').is_file() else None)
	with ThreadPoolExecutor(max_workers=4) as pool: results = list(pool.map(job,plans))
	passed = all(row['result']['status'] == 'EXPECTED_OUTCOME' for row in results)
	write(runtime/'result.json',dict(status=('CURRENT_BOOK_DOC_SCHEMA_PREVIEW_PASS' if a.docs_only else 'CURRENT_BOOK_NONREGRESSION_PASS') if passed else 'CURRENT_BOOK_NONREGRESSION_FAILURE',start_UTC=start,completed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),plans_sha256=sha(runtime/'plans.json'),suites=results,source_consumer_reuse_sha256=sha(runtime/'source-consumer-reuse.json'),scope='Only explicitly listed suites executed. Full lane replays 22 established native/ABI/owner/physical suites and exact unchanged source-consumer O0/O2 products under strict memory; docs-only retries four schema/extraction suites. No historical build relabeling, C0 memory or release waiver.'))
	assert passed


if __name__ == '__main__':
	main()
