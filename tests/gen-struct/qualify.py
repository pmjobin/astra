# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Current independent stage/layout checks and explicit memory comparisons."""
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
from execute import ROOT, FIXTURES, CASES, STAGES, run

LEGACY = {'semantic','core','cfg'}




def write(path, value):
	path.write_text(json.dumps(value,indent='\t')+'\n')


def audit(build, out, independent):
	commands = json.loads((build/'compile_commands.json').read_text())
	generated = [row for row in commands if row['file'].endswith('.c') and 'astrac.p/' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	assert independent is not None and (independent/'astrac').exists()
	execution = build/'tests/gen-struct/execution'
	native = json.loads((execution/'results.json').read_text())
	deterministic = []
	for name in [*CASES,'deep-64','unused','null']:
		source = execution/(name+'.astra') if name in ['deep-64','unused','null'] else FIXTURES/('gen-struct-'+name+'.astra')
		for stage in STAGES:
			data = run([independent/'astrac','--dump-'+stage,source]).encode()
			assert data == (execution/(name+'.'+stage)).read_bytes(), (name,stage)
			deterministic.append(dict(fixture=name,stage=stage,sha256=hashlib.sha256(data).hexdigest()))
	for stage in ['syntax','semantic','core','cfg','ssa','nabi']:
		for path in (ROOT/'bootstrap'/stage).glob('*.vala'):
			code = re.sub(r'/\*.*?\*/|//[^\n]*','',path.read_text(),flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.',code), path
			if stage in ['cfg','ssa','nabi']:
				# Current ABI shape/mode descriptors are valid here; a high-level
				# StructValue object or generic declaration model is not.
				assert not re.search(r'GenericStruct|CoreGenericStruct|GenericFieldPlace|\bStructValue\b',code), path
			if stage == 'core' and path.name != 'builder.vala':
				assert not re.search(r'GenericStructSymbol|CheckedGenericStruct|Astra\.Syntax',code), path
	for stage in ['cfg','ssa']:
		code = '\n'.join(path.read_text() for path in (ROOT/'bootstrap'/stage).glob('*.vala'))
		assert not re.search(r'\(\((?:Core|Cfg)LocalPlace\) (?:field|projection)\.aggregate\)',code)
		# Physical layouts use the same empty CPU/features, PIC/default target policy.
	tool = out/'layout'
	flags = run(['llvm-config','--cflags','--ldflags','--libs','core','irreader','native','--system-libs']).split()
	run(['cc','-std=c11','-Werror',ROOT/'tests/struct-agg/layout.c',*flags,'-o',tool])
	# Map exact instance inventory to ordinary Core name, then SSA order / LLVM name.
	ir = execution/'layout.llvm'
	ssa_names = re.findall(r'^\t\(struct "([^"]+)"', (execution/'layout.ssa').read_text(), re.M)
	llvm_names = re.findall(r'^%(astra\.struct\.\d+) = type ', ir.read_text(), re.M)
	assert len(ssa_names) == len(llvm_names)
	# LLVM prints named definitions in use order; their numeric names retain the
	# backend's SSA descriptor ordinal, independently of that textual order.
	mapping = {name: 'astra.struct.'+str(i) for i,name in enumerate(ssa_names)}
	assert set(mapping.values()) == set(llvm_names)
	measurements = run([tool, ir, *llvm_names])
	measured = dict(re.findall(r'^(astra\.struct\.\d+) (size=.*)$', measurements, re.M))
	instances = native['inventory']['layout']
	applications = {row['application']: row for row in instances}
	inventory = []
	for row in instances:
		name = f"astra.gen.struct.{row['definition']}.{row['ordinal']}"
		inventory.append(dict(**row, core_name=name, llvm_name=mapping[name], measured=measured[mapping[name]]))
	for application, control in [('Pair<int,f64>','PairControl'), ('Box<i16<8>>','VectorControl'), ('Pair<f64,f64>','InnerControl'), ('Bundle<f64>','BundleControl')]:
		row = applications[application]
		name = f"astra.gen.struct.{row['definition']}.{row['ordinal']}"
		assert measured[mapping[name]] == measured[mapping[control]], (application, control, measurements)
	signed = applications['Tagged<i8>']; unsigned = applications['Tagged<u8>']
	assert signed['ordinal'] != unsigned['ordinal']
	write(out/'layouts.json', dict(target_measurements=measurements, instances=inventory, controls={name: measured[mapping[name]] for name in ['PairControl','VectorControl','InnerControl','BundleControl']}))
	machine = []
	for fixture,name in [('basic','scalarized'), ('pointer','pay_for_use'), ('vector','scalarized'), ('f64','scalarized'), ('nested','scalarized'), ('generic-fn','astra.gen.0.0'), ('cap','astra.gen.0.0'), ('cap','astra.gen.0.2'), ('pointer','alias')]:
		ssa = (execution/(fixture+'.ssa')).read_text()
		ordinal = re.search(r'\(function #(\d+) "'+re.escape(name)+r'"',ssa)[1]
		assembly = (execution/(fixture+'-callable-O2-fma.machine')).read_text()
		symbol = 'astra.fn.'+ordinal
		body = re.search(r'^0+[0-9a-f]* <'+re.escape(symbol)+r'>:\n.*?(?=\n\n|\Z)',assembly,re.M|re.S)
		assert body, (fixture,name)
		machine.append(dict(fixture=fixture,name=name,symbol=symbol,assembly=body[0]))
	write(out/'independent-determinism.json', deterministic)
	print(json.dumps(dict(scope='current independently built compiler comparison', comparisons=len(deterministic))), flush=True)


def losses(text):
	text = re.sub(r'^==\d+== ?','',text,flags=re.M)
	records = re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)',text,flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+','ADDRESS',re.sub(r'loss record [\d,]+ of [\d,]+','loss record',record)) for record in records]


def memory(build, out, baseline):
	logs = out/'valgrind'; logs.mkdir(exist_ok=True)
	jobs = []
	stages = {'gen-struct-'+name for name in ['parser','semantic','core-standalone','monomorphizer-standalone','cfg-standalone','ssa-standalone','nabi-standalone','pipeline','llvm']}
	for root,prefix,names in [(build,'',stages|LEGACY),(baseline,'baseline-',LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names:
				jobs.append((prefix+test['name'],test['cmd'],test['workdir'] or str(root),dict(os.environ,**test['env']),0))
	execution = build/'tests/gen-struct/execution'
	for name in ['basic','nested','vector','f64','pointer','generic-fn','box-matrix']:
		for stage in ['semantics','core','instances','cfg','ssa']:
			jobs.append(('dump-'+name+'-'+stage,[str(build/'astrac'),'--dump-'+stage,str(FIXTURES/('gen-struct-'+name+'.astra'))],str(ROOT),os.environ,0))
	for name in ['cycle','invalid']:
		jobs.append(('diagnostic-'+name,[str(build/'astrac'),'--check',str(FIXTURES/('gen-struct-'+name+'.astra'))],str(ROOT),os.environ,1))
	for name in ['basic-O2','nested-O2','vector-O2','f64-O2','pointer-callable-O2-fma','box-matrix-O2','scalarize-O2','cap-O2','f32-bits-O2-fma','f64-bits-O2-fma','deep-64-O2','opaque-O2','cap-ieee-O2-fma']:
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
	build = args.build.resolve(); out = build/'qualification-gen-struct'; out.mkdir(exist_ok=True)
	if args.memory:
		assert args.baseline_build is not None
		memory(build,out,args.baseline_build.resolve())
	else:
		audit(build,out,args.independent_build.resolve() if args.independent_build else None)
