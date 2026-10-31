# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproducible baseline, strict-build, layout, determinism and memory evidence."""
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
from execute import ROOT, FIXTURES, CASES, run

BASELINE = '1fc89849dde493cbe74128a910a449729e92bf2b'
EXTENSIONS = {'.syntax','.semantics','.core','.instances','.cfg','.ssa','.nabi','.cabi','.ll','.stderr'}
LEGACY = {'semantic','core','cfg'}


def git(*args):
	return subprocess.check_output(['git',*args],cwd=ROOT)


def write(path, value):
	path.write_text(json.dumps(value,indent='\t')+'\n')


def audit(build, out, independent):
	tests = [json.loads(line) for line in (build/'meson-logs/testlog.json').read_text().splitlines()]
	assert len(tests) == len(json.loads((build/'meson-info/intro-tests.json').read_text())) and all(row['result'] == 'OK' for row in tests)
	goldens = []
	for name in git('ls-tree','-r','--name-only',BASELINE,'tests').decode().splitlines():
		if Path(name).suffix not in EXTENSIONS:
			continue
		content = (ROOT/name).read_bytes(); assert content == git('show',BASELINE+':'+name), name
		goldens.append(dict(path=name,sha256=hashlib.sha256(content).hexdigest()))
	for directory in ['bootstrap/nabi','bootstrap/cabi','bootstrap/vapi','bootstrap/foreign']:
		assert git('diff',BASELINE,'--',directory) == b'', directory
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	assert independent is not None and (independent/'astrac').exists()
	execution = build/'tests/struct-agg/execution'
	native = json.loads((execution/'results.json').read_text())
	deterministic = []
	for name in [*CASES,'matrix','deep-64']:
		source = execution/(name+'.astra') if name in ['matrix','deep-64'] else FIXTURES/('struct-agg-'+name+'.astra')
		for stage in ['syntax','semantics','core','cfg','ssa','nabi','llvm']:
			data = run([independent/'astrac','--dump-'+stage,source]).encode()
			assert data == (execution/(name+'.'+stage)).read_bytes(), (name,stage)
			deterministic.append(dict(fixture=name,stage=stage,sha256=hashlib.sha256(data).hexdigest()))
	for stage in ['syntax','semantic','core','cfg','ssa','nabi']:
		for path in (ROOT/'bootstrap'/stage).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*','',path.read_text(),flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.',code), path
			assert not re.search(r'GenericStruct|CoreGenericStruct|NestedFieldPlace|DeepNestedFieldPlace|StructValue',code), path
	for stage in ['cfg','ssa']:
		code = '\n'.join(path.read_text() for path in (ROOT/'bootstrap'/stage).glob('*.vala'))
		assert not re.search(r'\(\((?:Core|Cfg)LocalPlace\) (?:field|projection)\.aggregate\)',code)
		# Physical layouts use the same empty CPU/features, PIC/default target policy.
	tool = out/'layout'
	flags = run(['llvm-config','--cflags','--ldflags','--libs','core','irreader','native','--system-libs']).split()
	run(['cc','-std=c11','-Werror',ROOT/'tests/struct-agg/layout.c',*flags,'-o',tool])
	layouts = {}
	for name in ['pointer','addressed','vector','f64']:
		ir = execution/(name+'.llvm')
		names = re.findall(r'^%(astra\.struct\.\d+) = type ',ir.read_text(),re.M)
		layouts[name] = run([tool,ir,*names])
	write(out/'layouts.json',layouts)
	machine = []
	for fixture,name in [('scalarize','f'),('addressed','pay_for_use'),('vector','mutate'),('pointer','aliases'),('f64','roundtrip'),('f64','separate')]:
		ssa = (execution/(fixture+'.ssa')).read_text()
		ordinal = re.search(r'\(function #(\d+) "'+name+r'"',ssa)[1]
		assembly = (execution/(fixture+'-callable-O2-fma.machine')).read_text()
		symbol = 'astra.fn.'+ordinal
		body = re.search(r'^0+[0-9a-f]* <'+re.escape(symbol)+r'>:\n.*?(?=\n\n|\Z)',assembly,re.M|re.S)
		assert body, (fixture,name)
		machine.append(dict(fixture=fixture,name=name,symbol=symbol,assembly=body[0]))
	plans = [int(match[1]) for row in tests if (match := re.search(r'^1\.\.(\d+)$',row.get('stdout',''),re.M))]
	summary = dict(baseline=BASELINE,meson_tests=len(tests),tap_cases=sum(plans),tap_suites=len(plans),strict_generated_c_commands=len(generated),unchanged_baseline_goldens=len(goldens),changed_baseline_goldens=[],new_goldens=sum(p.suffix in EXTENSIONS for p in FIXTURES.iterdir()),native_runs=len(native['runs']),vector_shapes=len(native['shapes']),independent_build_comparisons=len(deterministic),fresh_process_comparisons=len(native['deterministic']),firewall_linkage_tests=sum(any(x in row['name'] for x in ['no-llvm','links-qualified-llvm','linkage-rejects','firewall-rejects']) for row in tests),machine_audits=len(machine),dependencies_added=0)
	for name,data in [('summary',summary),('unchanged-goldens',goldens),('independent-determinism',deterministic),('machine',machine)]:
		write(out/(name+'.json'),data)
	print(json.dumps(summary),flush=True)


def losses(text):
	text = re.sub(r'^==\d+== ?','',text,flags=re.M)
	records = re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)',text,flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+','ADDRESS',re.sub(r'loss record [\d,]+ of [\d,]+','loss record',record)) for record in records]


def memory(build, out, baseline):
	logs = out/'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	stages = {'struct-agg-'+name for name in ['parser','semantic','core-standalone','cfg-standalone','ssa-standalone','nabi-standalone','pipeline','llvm']}
	for root,prefix,names in [(build,'',stages|LEGACY),(baseline,'baseline-',LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names:
				jobs.append((prefix+test['name'],test['cmd'],test['workdir'] or str(root),dict(os.environ,**test['env']),0))
	execution = build/'tests/struct-agg/execution'
	for name in ['basic','deep','vector','f64','pointer','method']:
		for stage in ['semantics','core','cfg','ssa']:
			jobs.append(('dump-'+name+'-'+stage,[str(build/'astrac'),'--dump-'+stage,str(FIXTURES/('struct-agg-'+name+'.astra'))],str(ROOT),os.environ,0))
	for name in ['cycle','invalid']:
		jobs.append(('diagnostic-'+name,[str(build/'astrac'),'--check',str(FIXTURES/('struct-agg-'+name+'.astra'))],str(ROOT),os.environ,1))
	for name in ['basic-O2','deep-O2','vector-O2','f64-O2','pointer-callable-O2-fma','addressed-O2','scalarize-O2','f32-bits-O2-fma','f64-bits-O2-fma','deep-64-O2']:
		jobs.append(('run-'+name,[str(execution/name)],str(ROOT),os.environ,0))

	def measure(job):
		name,argv,cwd,env,status = job
		command = ['valgrind','--vgdb=no','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99','--log-file='+str(logs/(name+'.log')),*argv]
		result = subprocess.run(command,cwd=cwd,env=env,capture_output=True,text=True)
		(logs/(name+'.stdout')).write_text(result.stdout); (logs/(name+'.stderr')).write_text(result.stderr)
		text = (logs/(name+'.log')).read_text(); assert 'ERROR SUMMARY:' in text,name
		def number(pattern):
			match = re.search(pattern,text); return int(match[1].replace(',','')) if match else 0
		return dict(name=name,exit=result.returncode,expected=status,errors=number(r'ERROR SUMMARY: ([\d,]+) errors'),definite=number(r'definitely lost: ([\d,]+) bytes'),indirect=number(r'indirectly lost: ([\d,]+) bytes'),possible=number(r'possibly lost: ([\d,]+) bytes'),suppressed=number(r'suppressed: ([\d,]+) from'),reachable=number(r'still reachable: ([\d,]+) bytes'),lost_records=losses(text))

	with ThreadPoolExecutor(max_workers=4) as pool:
		rows = list(pool.map(measure,jobs))
	write(logs/'results.json',rows)
	by_name = {row['name']:row for row in rows}
	for row in rows:
		if row['name'].removeprefix('baseline-') in LEGACY:
			assert row['exit'] == 99 and row['errors'] == 1 and row['definite'] == 16384 and row['indirect'] == row['possible'] == row['suppressed'] == 0, row
			assert len(row['lost_records']) == 1 and 'g_malloc' in row['lost_records'][0] and 'call_init' in row['lost_records'][0], row
			if not row['name'].startswith('baseline-'):
				assert row['lost_records'] == by_name['baseline-'+row['name']]['lost_records'], row
		else:
			assert row['exit'] == row['expected'] and row['errors'] == row['definite'] == row['indirect'] == row['possible'] == row['suppressed'] == 0, row
	summary = dict(current_runs=len(rows)-len(LEGACY),baseline_runs=len(LEGACY),matching_legacy_startup_losses=len(LEGACY),new_astra_errors=0,new_astra_lost_bytes=0)
	write(logs/'summary.json',summary); print(json.dumps(summary),flush=True)


if __name__ == '__main__':
	parser = argparse.ArgumentParser(); parser.add_argument('build',type=Path); parser.add_argument('--independent-build',type=Path); parser.add_argument('--baseline-build',type=Path); parser.add_argument('--memory',action='store_true'); args = parser.parse_args()
	build = args.build.resolve(); out = build/'qualification-struct-agg'; out.mkdir(exist_ok=True)
	if args.memory:
		assert args.baseline_build is not None
		memory(build,out,args.baseline_build.resolve())
	else:
		audit(build,out,args.independent_build.resolve() if args.independent_build else None)
