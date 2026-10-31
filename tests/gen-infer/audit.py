# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Accepted baseline, independent compilation, stage isolation and memory audit."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from qualify import CASES, FIXTURES, ROOT, STAGES, run
from negative import CASES as NEGATIVES

BASELINE = '93de06520e562ccda08c4281b39efe409bfc610e'
EXTENSIONS = {'.syntax','.semantics','.core','.instances','.cfg','.ssa','.nabi','.cabi','.ll','.stderr'}


def write(path, data):
	path.write_text(json.dumps(data,indent='\t')+'\n')


def audit(build, independent, baseline, out):
	goldens = []
	names = subprocess.check_output(['git','ls-tree','-r','--name-only',BASELINE,'tests'],cwd=ROOT).decode().splitlines()
	for name in names:
		if Path(name).suffix not in EXTENSIONS:
			continue
		before = subprocess.check_output(['git','show',BASELINE+':'+name],cwd=ROOT)
		assert before == (ROOT/name).read_bytes(), ('accepted golden changed',name)
		goldens.append(dict(path=name,sha256=hashlib.sha256(before).hexdigest()))
	comparisons = []; baseline_comparisons = []; machine = []
	for name in CASES:
		for prefix in ['gen-infer','explicit']:
			for stage in STAGES:
				args = ['--dump-'+stage,FIXTURES/(prefix+'-'+name+'.astra')]+([] if stage=='syntax' else ['--vapi',FIXTURES/'runtime.vapi'])
				data = run([independent/'astrac',*args])
				assert data == (build/'tests/gen-infer/qualification'/(prefix+'-'+name+'.'+stage)).read_text(), (name,prefix,stage,'independent build')
				comparisons.append(prefix+'-'+name+':'+stage)
				if prefix=='explicit':
					assert data == run([baseline/'astrac',*args]), (name,stage,'explicit baseline semantics changed')
					baseline_comparisons.append(name+':'+stage)
			for mode in ['O0','O2','fma']:
				path=Path('tests/gen-infer/qualification')/(prefix+'-'+name+'-'+mode+'.machine')
				# objdump headers carry the build directory; instructions and relocations do not.
				assert (build/path).read_text().split('Disassembly of section',1)[1] == (independent/path).read_text().split('Disassembly of section',1)[1]
				machine.append(prefix+'-'+name+':'+mode)
	for name in ['gen-infer-multisource','outer-multisource']:
		for stage in STAGES:
			path=Path('tests/gen-infer/qualification')/(name+'.'+stage)
			assert (build/path).read_bytes() == (independent/path).read_bytes(), (name,stage)
			comparisons.append(name+':'+stage)
			# Establish the direct owned-producer boundary against the accepted compiler.
	producer_controls = []
	for name in ['direct-resource-producer','direct-native-resource-producer','direct-class-producer','direct-outer-owned-producer']:
		source=NEGATIVES[name][0]
		type_name='T' if 'outer-owned' in name else 'C' if 'class' in name else 'Resource'
		source=source.replace('drop(', 'drop<'+type_name+'>(').replace('relay(move', 'relay<T>(move')
		path=out/(name+'-explicit.astra');path.write_text(source+'\n')
		for compiler in [baseline/'astrac',build/'astrac']:
			p=subprocess.run(list(map(str,[compiler,'--check',path,'--vapi',FIXTURES/'runtime.vapi'])),capture_output=True,text=True)
			assert p.returncode==1 and "requires explicit 'move owner'" in p.stderr, (name,compiler,p.returncode,p.stderr)
			producer_controls.append(dict(name=name,compiler=str(compiler),diagnostic=p.stderr))
			# Semantic-only inference classes may not enter stage-independent targets.
	for directory in ['bootstrap/core','bootstrap/cfg','bootstrap/ssa','bootstrap/nabi','bootstrap/cabi','bootstrap/backend']:
		for path in (ROOT/directory).rglob('*.vala'):
			assert not re.search(r'GenericCallInference|GenericInferenceObservation|GenericCallContext|SemanticOwnershipFlow|InferredGenericType|TypeVariable',path.read_text()),path
	for path in [build/'tests/gen/astra-gen-core',build/'tests/gen/astra-gen-cfg',build/'tests/gen/astra-gen-ssa',build/'tests/sources/astra-sources-nabi',build/'tests/sources/astra-sources-cabi',build/'tests/sources/astra-sources-llvm-standalone']:
		symbols=run(['nm','-a',path])
		assert not re.search(r'astra_semantic_(generic_call_inference|generic_inference_observation|generic_call_context|semantic_ownership_flow)',symbols),path
	tests=[json.loads(line) for line in (build/'meson-logs/gen-infer-final.json').read_text().splitlines()]
	assert len(tests)==len(json.loads((build/'meson-info/intro-tests.json').read_text()))
	assert all(row['result']=='OK' for row in tests),[(row['name'],row['result']) for row in tests if row['result']!='OK']
	plans=[int(m[1]) for row in tests if (m:=re.search(r'^1\.\.(\d+)$',row.get('stdout',''),re.M))]
	commands=json.loads((build/'compile_commands.json').read_text())
	generated=[row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	native=json.loads((build/'tests/gen-infer/qualification/results.json').read_text())
	negative=json.loads((build/'tests/gen-infer/negative/results.json').read_text())
	summary=dict(baseline=BASELINE,meson_tests=len(tests),tap_suites=len(plans),tap_cases=sum(plans),strict_generated_c_commands=len(generated),baseline_goldens=len(goldens),changed_baseline_goldens=[],superseded_assertions=['tests/gen/semantic.vala: omitted id(42) now accepts','tests/infer/negative.py: omitted identity(1) replaced by phantom marker(1)'],explicit_baseline_comparisons=len(baseline_comparisons),independent_build_comparisons=len(comparisons),independent_machine_comparisons=len(machine),stage_pairs=len(native['pairs']),fresh_process_comparisons=len(native['deterministic']),source_permutations=len(native['permutations']),permutation_stage_comparisons=sum(row['stages'] for row in native['permutations']),runtime_executions=len(native['runs']),machine_pairs=len(native['machine_pairs']),negative_stage_checks=len(negative),stage_lifetime_fixtures=len(CASES),firewall_linkage_tests=sum(any(x in row['name'] for x in ['no-llvm','links-qualified-llvm','linkage-rejects','firewall-rejects']) for row in tests),production_dependencies_added=0)
	write(out/'goldens.json',goldens);write(out/'determinism.json',comparisons);write(out/'explicit-baseline.json',baseline_comparisons);write(out/'producer-boundaries.json',producer_controls);write(out/'summary.json',summary)
	print(json.dumps(summary),flush=True)


def memory(build, out):
	logs=out/'valgrind';logs.mkdir(exist_ok=True)
	jobs=[]
	for name in ['semantic','pipeline']:
		jobs.append(('test-'+name,[build/'tests/gen-infer'/('astra-gen-infer-'+name),'--tap'],0,None))
	for name in CASES:
		for stage in STAGES[1:]:
			jobs.append(('dump-'+name+'-'+stage,[build/'astrac','--dump-'+stage,FIXTURES/('gen-infer-'+name+'.astra'),'--vapi',FIXTURES/'runtime.vapi'],0,None))
	for name in NEGATIVES:
		jobs.append(('negative-'+name,[build/'astrac','--dump-semantics',build/'tests/gen-infer/negative'/(name+'.astra'),'--vapi',FIXTURES/'runtime.vapi'],1,''))
	native=json.loads((build/'tests/gen-infer/qualification/results.json').read_text())
	for row in native['runs']:
		jobs.append(('run-'+row['name'],[build/'tests/gen-infer/qualification'/row['name']],0,row['trace']))

	def measure(job):
		name,argv,status,expected=job;path=logs/(name+'.log')
		p=subprocess.run(list(map(str,['valgrind','--vgdb=no','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99','--log-file='+str(path),*argv])),cwd=ROOT,capture_output=True,text=True,env=dict(os.environ,CCACHE_DISABLE='1'))
		(logs/(name+'.stdout')).write_text(p.stdout);(logs/(name+'.stderr')).write_text(p.stderr)
		text=path.read_text();assert 'ERROR SUMMARY:' in text,name
		def number(pattern):
			match=re.search(pattern,text)
			return int(match[1].replace(',','')) if match else 0
		return dict(name=name,status=p.returncode,expected_status=status,errors=number(r'ERROR SUMMARY: ([\d,]+) errors'),definite=number(r'definitely lost: ([\d,]+) bytes'),indirect=number(r'indirectly lost: ([\d,]+) bytes'),possible=number(r'possibly lost: ([\d,]+) bytes'),output_matches=expected is None or expected==p.stdout)

	with ThreadPoolExecutor(max_workers=4) as pool:
		rows=list(pool.map(measure,jobs))
	write(logs/'results.json',rows)
	bad=[row for row in rows if row['status']!=row['expected_status'] or row['errors'] or row['definite'] or row['indirect'] or row['possible'] or not row['output_matches']]
	assert not bad,bad
	summary=dict(runs=len(rows),errors=0,definite=0,indirect=0,possible=0,suppressions=0)
	write(logs/'summary.json',summary);print(json.dumps(summary),flush=True)


if __name__=='__main__':
	parser=argparse.ArgumentParser();parser.add_argument('build',type=Path);parser.add_argument('--independent-build',type=Path);parser.add_argument('--baseline-build',type=Path,default=ROOT/'build-sources-1');parser.add_argument('--memory',action='store_true');args=parser.parse_args()
	build=args.build.resolve();out=build/'qualification-gen-infer';out.mkdir(exist_ok=True)
	if args.memory:
		memory(build,out)
	else:
		assert args.independent_build
		audit(build,args.independent_build.resolve(),args.baseline_build.resolve(),out)
