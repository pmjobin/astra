# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce GEN-CAP-1 golden, strict-build, stage, determinism and memory audits."""
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
from execute import CASES, FIXTURES, ROOT

BASELINE = '0bff0c63742648e6db757314c6312ba203efb09a'
PRIOR = '07aeb36b4af337add8fd886992af8f6cb218047b'
STAGES = ['parser','semantic','core-standalone','monomorphizer-standalone','cfg-standalone','ssa-standalone','nabi-standalone','pipeline','llvm']
SUITES = {'gen-cap-'+stage for stage in STAGES}
LEGACY = {'semantic','core','cfg'}
EXTENSIONS = {'.syntax','.semantics','.core','.instances','.cfg','.ssa','.nabi','.cabi','.ll','.stderr'}


def git(*args):
	return subprocess.check_output(['git',*args],cwd=ROOT)


def write(path, value):
	path.write_text(json.dumps(value,indent='\t')+'\n')


def audit(build,out,independent,testlog=None):
	tests=[json.loads(line) for line in (testlog or build/'meson-logs/testlog.json').read_text().splitlines()]
	assert len(tests)==len(json.loads((build/'meson-info/intro-tests.json').read_text())) and all(row['result']=='OK' for row in tests)
	goldens=[]
	for name in git('ls-tree','-r','--name-only',BASELINE,'tests').decode().splitlines():
		if Path(name).suffix not in EXTENSIONS: continue
		content=(ROOT/name).read_bytes(); assert content==git('show',BASELINE+':'+name),name
		goldens.append(dict(path=name,sha256=hashlib.sha256(content).hexdigest()))
	prior={name for name in git('ls-tree','-r','--name-only',PRIOR,'tests').decode().splitlines() if Path(name).suffix in EXTENSIONS}
	assert len(prior)==739 and all(name in {row['path'] for row in goldens} for name in prior)
	for directory in ['bootstrap/cfg','bootstrap/ssa','bootstrap/nabi','bootstrap/cabi','bootstrap/vapi','bootstrap/foreign','bootstrap/backend/llvm']:
		assert git('diff',BASELINE,'--',directory)==b'',directory
	for stage in ['syntax','semantic','core','cfg','ssa','nabi']:
		for path in (ROOT/'bootstrap'/stage).glob('*.vala'):
			code=re.sub(r'/\*.*?\*/|//[^\n]*','',path.read_text(),flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.',code),path
			if stage in ['cfg','ssa','nabi']:
				assert not re.search(r'\b(?:GenericCapability\w*|GenericOperationKind|CoreGeneric\w*|TypeParameterType)\b',code),path
	cloner=(ROOT/'bootstrap/core/generic-monomorphizer.vala').read_text()
	assert not re.search(r'\b(?:Parser|Syntax|SemanticAnalyzer|Checked\w*|FunctionSymbol|MethodSymbol|PropertySymbol|FieldSymbol)\b',cloner)
	old=git('show',BASELINE+':src/core/core-generics.vala').decode(); current=(ROOT/'bootstrap/core/core-generics.vala').read_text()
	assert current[current.index('\tpublic enum GenericInstanceState'):] == old[old.index('\tpublic enum GenericInstanceState'):]
	assert 'CoreVerifier.verify_concrete (program)' in (ROOT/'bootstrap/cfg/cfg-builder.vala').read_text()
	commands=json.loads((build/'compile_commands.json').read_text()); generated=[row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	assert independent is not None and (independent/'astrac').exists()
	deterministic=[]
	execution=build/'tests/gen-cap/execution'; native=json.loads((execution/'results.json').read_text())
	for name in [*CASES,'matrix']:
		source=execution/'matrix.astra' if name=='matrix' else FIXTURES/f'gen-cap-{name}.astra'
		options=['--vapi',str(ROOT/'tests/obj-life/fixtures/lifecycle.vapi')] if name=='owned' else []
		for stage in ['semantics','core','instances','llvm']:
			actual=subprocess.check_output([str(independent/'astrac'),'--dump-'+stage,str(source),*options],cwd=ROOT)
			assert actual==(execution/(name+'.'+stage)).read_bytes(),(name,stage)
			deterministic.append(dict(fixture=name,stage=stage,sha256=hashlib.sha256(actual).hexdigest()))
	probes = {
		'same-vector': ("bool same<T>(T a,T b) where T : Eq {return a==b;}bool root(i16<8> a,i16<8> b){return same<i16<8>>(a,b);}", "type argument 'i16<8>' does not satisfy capability 'Eq' required by type parameter 'T' of generic function 'same'"),
		'missing-outer': ("bool same<T>(T a,T b) where T : Eq {return a==b;}bool outer<T>(T a,T b){return same<T>(a,b);}bool root(){return outer<int>(1,1);}", "type argument 'T' does not satisfy capability 'Eq'"),
		'phantom': ("int tag<T>() where T : Eq {return 1;}int root(){return tag<i16<8>>();}", "does not satisfy capability 'Eq'"),
		'generic-literal': ("T add<T>(T a) where T : Numeric {return a+1;}", "generic literals cannot be contextualized"),
		'no-eq-implication': ("bool same<T>(T a,T b) where T : Ordered {return a==b;}", "requires explicit capability 'Eq'"),
		'no-ordered-implication': ("bool less<T>(T a,T b) where T : Numeric {return a<b;}", "requires explicit capability 'Ordered'")
	}
	negative=[]
	for name,(source,diagnostic) in probes.items():
		path=out/(name+'.astra'); path.write_text(source+'\n')
		result=subprocess.run([str(build/'astrac'),'--dump-instances',str(path)],capture_output=True,text=True)
		assert result.returncode==1 and result.stdout=='' and diagnostic in result.stderr,(name,result)
		negative.append(dict(name=name,diagnostic=result.stderr.strip(),instance_output_bytes=len(result.stdout)))
	write(out/'negative-probes.json',negative)
	# Representative assembly with exact source/Core/SSA-to-physical symbol mapping.
	machine=[]
	default_machine={}
	for fixture in ['matrix','ordered','bitwise','shift','property']:
		obj=out/('default-'+fixture+'.o')
		subprocess.run(['llc','-O2','-filetype=obj','-relocation-model=pic',str(execution/(fixture+'-callable-O2.ll')),'-o',str(obj)],check=True,capture_output=True)
		default_machine[fixture]=subprocess.check_output(['objdump','-dr',str(obj)],text=True)
		(out/('default-'+fixture+'.machine')).write_text(default_machine[fixture])
	for label,fixture,name,arguments in [('same<int>','matrix','eq',['int']),('same<f64>','matrix','eq',['f64']),('max<i32>','ordered','max_value',['int']),('max<u32>','ordered','max_value',['u32']),('max<f64>','ordered','max_value',['f64']),('add<int>','matrix','add',['int']),('add<f64>','matrix','add',['f64']),('mask<u32>','bitwise','mask',['u32']),('shift<i32>','shift','shift',['int']),('shift<u32>','shift','shift',['u32'])]:
		row=next(row for row in native['inventories'][fixture] if row['name']==name and row['arguments']==arguments)
		core_name=f"astra.gen.{row['definition']}.{row['ordinal']}"
		ssa=(execution/(fixture+'.ssa')).read_text(); ordinal=re.search(r'\(function #(\d+) "'+re.escape(core_name)+'"',ssa)[1]
		symbol='astra.fn.'+ordinal; assembly=default_machine[fixture]
		body=re.search(r'^0+[0-9a-f]* <'+re.escape(symbol)+r'>:\n.*?(?=\n\n|\Z)',assembly,re.M|re.S)
		assert body,(label,symbol)
		machine.append(dict(label=label,fixture=fixture,source_generic=name,arguments=arguments,symbol=symbol,assembly=body[0]))
	property_ssa=(execution/'property.ssa').read_text()
	getter=re.search(r'^\t\(property-getter #\d+ \(property \S+ #(\d+)\) \(declaring-(class|struct) #(\d+)\)',property_ssa,re.M); assert getter
	assembly=default_machine['property']; symbol=f'astra.propget.{getter[2]}.{getter[3]}.{getter[1]}'
	assert '@'+symbol+'(' in (execution/'property-callable-O2.ll').read_text()
	body=re.search(r'^0+[0-9a-f]* <'+re.escape(symbol)+r'>:\n.*?(?=\n\n|\Z)',assembly,re.M|re.S); assert body
	machine.append(dict(label='generic property caller',fixture='property',symbol=symbol,assembly=body[0]))
	(out/'machine.txt').write_text('Default x86-64; O2 callable functions; instruction choices are evidence only.\nEq fixture names eq<int>/eq<f64> implement same<T>.\n\n'+'\n\n'.join(row['label']+' ('+row['fixture']+'::'+row['symbol']+')\n'+row['assembly'] for row in machine)+'\n')
	plans=[int(plan) for row in tests for plan in re.findall(r'^1\.\.(\d+)\s*$',row['stdout'],re.M)]
	counts={prefix:sum(row['name'].split(':')[-1].startswith(prefix+'-') for row in tests) for prefix in ['gen-cap','gen','f32','f64','prop','cabi','vapi']}
	summary=dict(baseline=BASELINE,meson_tests=len(tests),tap_cases=sum(plans),tap_suites=len(plans),test_counts=counts,strict_generated_c_commands=len(generated),unchanged_baseline_goldens=len(goldens),unchanged_pre_gen_goldens=len(prior),unchanged_gen_goldens=sum('/gen/' in row['path'] for row in goldens),new_goldens=sum(path.suffix in EXTENSIONS for path in FIXTURES.iterdir()),native_runs=len(native['runs']),matrix_checks=len(native['matrix_checks']),floating_cases={name:len(rows) for name,rows in native['floating_patterns'].items()},independent_build_comparisons=len(deterministic),fresh_process_comparisons=len(native['deterministic']),machine_audits=len(machine),firewall_linkage_tests=sum(any(marker in row['name'] for marker in ['no-llvm','links-qualified-llvm','linkage-rejects','firewall-rejects']) for row in tests),negative_inventory_probes=len(negative),dependencies_added=0)
	for name,data in [('summary',summary),('unchanged-goldens',goldens),('independent-determinism',deterministic),('machine',machine)]: write(out/(name+'.json'),data)
	print(json.dumps(summary),flush=True)


def losses(text):
	text=re.sub(r'^==\d+== ?','',text,flags=re.M)
	records=re.findall(r'[\d,]+ bytes in [\d,]+ blocks are (?:definitely|indirectly|possibly) lost in loss record[^\n]*\n.*?(?=\n\n|\Z)',text,flags=re.S)
	return [re.sub(r'0x[0-9A-Fa-f]+','ADDRESS',re.sub(r'loss record [\d,]+ of [\d,]+','loss record',record)) for record in records]


def memory(build,out,baseline):
	assert baseline is not None and (baseline/'astrac').is_file()
	assert 'ASTRA-GEN-1' in subprocess.check_output([str(baseline/'astrac'),'--version'],text=True)
	logs=out/'valgrind'; logs.mkdir(exist_ok=True); jobs=[]
	extra={'gen-'+stage for stage in STAGES}|{'f32-semantic-standalone','f32-pipeline','f32-llvm','f64-semantic-standalone','f64-pipeline','f64-llvm','prop-pipeline','prop-llvm'}
	for root,prefix,names in [(build,'',SUITES|LEGACY|extra),(baseline,'baseline-',LEGACY)]:
		for test in json.loads((root/'meson-info/intro-tests.json').read_text()):
			if test['name'] in names: jobs.append((prefix+test['name'],test['cmd'],test['workdir'] or str(root),dict(os.environ,**test['env']),0,None))
	execution=build/'tests/gen-cap/execution'
	for row in json.loads((execution/'results.json').read_text())['runs']: jobs.append(('run-'+row['name'],[str(execution/row['name'])],str(ROOT),os.environ,row['status'],row['output']))
	for name in CASES:
		for stage in ['syntax','semantics','core','instances','cfg','ssa','nabi','llvm']:
			options=['--vapi',str(ROOT/'tests/obj-life/fixtures/lifecycle.vapi')] if name=='owned' and stage!='syntax' else []
			jobs.append(('dump-'+name+'-'+stage,[str(build/'astrac'),'--dump-'+stage,str(FIXTURES/f'gen-cap-{name}.astra'),*options],str(ROOT),os.environ,0,None))
	jobs.append(('invalid-unused-definition',[str(build/'astrac'),'--check',str(FIXTURES/'gen-cap-invalid.astra')],str(ROOT),os.environ,1,''))
	assert len({job[0] for job in jobs})==len(jobs)

	def measure(job):
		name,argv,cwd,env,status,output=job
		command=['valgrind','--vgdb=no','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99','--log-file='+str(logs/(name+'.log')),*argv]
		p=subprocess.run(command,cwd=cwd,env=env,capture_output=True,text=True)
		(logs/(name+'.stdout')).write_text(p.stdout); (logs/(name+'.stderr')).write_text(p.stderr)
		text=(logs/(name+'.log')).read_text(); assert 'ERROR SUMMARY:' in text,name
		def number(pattern):
			match=re.search(pattern,text); return int(match[1].replace(',','')) if match else 0
		return dict(name=name,exit=p.returncode,expected=status,output_matches=output is None or output==p.stdout,errors=number(r'ERROR SUMMARY: ([\d,]+) errors'),definite=number(r'definitely lost: ([\d,]+) bytes'),indirect=number(r'indirectly lost: ([\d,]+) bytes'),possible=number(r'possibly lost: ([\d,]+) bytes'),suppressed=number(r'suppressed: ([\d,]+) from'),reachable=number(r'still reachable: ([\d,]+) bytes'),lost_records=losses(text))

	with ThreadPoolExecutor(max_workers=4) as pool: rows=list(pool.map(measure,jobs))
	write(logs/'results.json',rows); by_name={row['name']:row for row in rows}
	for row in rows:
		name=row['name']
		if name.removeprefix('baseline-') in LEGACY:
			assert row['exit']==99 and row['errors']==1 and row['definite']==16384 and row['indirect']==row['possible']==row['suppressed']==0,row
			assert len(row['lost_records'])==1 and 'g_malloc' in row['lost_records'][0] and 'call_init' in row['lost_records'][0],row
			assert row['lost_records']==by_name['baseline-'+name.removeprefix('baseline-')]['lost_records'],row
		else:
			assert row['exit']==row['expected'] and row['output_matches'] and row['errors']==row['definite']==row['indirect']==row['possible']==row['suppressed']==0,row
			if name.startswith('run-') and row['expected']==42: assert row['reachable']==0,row
	summary=dict(current_runs=len(rows)-len(LEGACY),baseline_runs=len(LEGACY),clean_current_runs=len(rows)-2*len(LEGACY),matching_legacy_startup_losses=len(LEGACY),new_astra_errors=0,new_astra_lost_bytes=0)
	write(logs/'summary.json',summary); print(json.dumps(summary),flush=True)


if __name__=='__main__':
	parser=argparse.ArgumentParser(); parser.add_argument('build',type=Path); parser.add_argument('--independent-build',type=Path); parser.add_argument('--baseline-build',type=Path); parser.add_argument('--testlog',type=Path); parser.add_argument('--memory',action='store_true'); args=parser.parse_args()
	build=args.build.resolve(); out=build/'qualification-gen-cap'; out.mkdir(exist_ok=True)
	if args.memory: memory(build,out,args.baseline_build.resolve() if args.baseline_build else None)
	else: audit(build,out,args.independent_build.resolve() if args.independent_build else None,args.testlog.resolve() if args.testlog else None)
