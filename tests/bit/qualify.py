# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reproduce bit/shift LLVM poison, predecessor, object, machine and memory audits."""
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import argparse
import importlib.util
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import BASELINE, FIXTURES, ROOT, bindings

spec = importlib.util.spec_from_file_location('astra_scalar_qualification', ROOT/'tests/f32/qualify.py')
scalar = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scalar)


def run(argv):
	r = subprocess.run(list(map(str,argv)), cwd=ROOT, capture_output=True, text=True)
	assert r.returncode == 0, (argv,r.returncode,r.stdout,r.stderr)
	return r.stdout


def guarded_shifts(llvm):
	guards = 0
	for function in re.findall(r'(?ms)^define [^\n]+\{\n(.*?)^}', llvm):
		blocks = {}
		for line in function.splitlines():
			label = re.match(r'^([\w.]+):',line)
			if label:
				block = label[1]
				blocks[block] = []
			elif line.strip():
				blocks[block].append(line.strip())
		for block, lines in blocks.items():
			for line in lines:
				shift = re.match(r'%(v\d+) = (?:shl|ashr|lshr) ',line)
				if not shift:
					continue
				name = shift[1]
				# Constants need no guard; a dynamic physical count does.
				if not re.search(r', %(?:\w|\.)+$',line):
					continue
				assert block == name+'.valid', (block,line)
				trap = blocks[name+'.trap']
				assert trap == ['call void @llvm.trap()', 'unreachable'], trap
				predecessors = [src for src, body in blocks.items() if any('label %'+name+'.valid' in row for row in body)]
				assert len(predecessors) == 1
				guard = blocks[predecessors[0]]
				assert guard[-1] == f'br i1 %{name}.'+('invalid' if any('.negative = icmp slt' in row for row in guard) else 'oversized')+f', label %{name}.trap, label %{name}.valid'
				assert any(name+'.oversized = icmp ' in row for row in guard)
				assert not any(re.search(r' = (?:shl|ashr|lshr) ',row) and row.startswith('%'+name+' =') for row in guard)
				guards += 1
	return guards


def optimized_poison(llvm):
	# O2 can erase irrelevant splat lanes. Qualify their uses explicitly:
	# only inserted lane zero is selected, and the poison second vector is
	# never selected. No poison value may be a shift operand or result.
	assert not re.search(r'\bundef\b',llvm)
	count=0
	for function in re.findall(r'(?ms)^define [^\n]+\{\n(.*?)^}',llvm):
		lines=function.splitlines()
		for line in lines:
			if not re.search(r'\bpoison\b',line):
				continue
			count+=1
			seed=re.search(r'(%[\w.]+) = insertelement <\d+ x i\d+> poison, i\d+ [^,]+, i(?:32|64) 0$',line)
			if seed:
				users=[row for row in lines if row!=line and re.search(re.escape(seed[1])+r'(?![\w.])',row)]
				assert users and all('shufflevector ' in row and row.endswith('zeroinitializer') for row in users),users
				continue
			shuffle=re.search(r'shufflevector <(\d+) x i\d+> %([\w.]+), <\d+ x i\d+> poison, <\d+ x i32> (.+)$',line)
			assert shuffle,line
			selectors=shuffle[3]
			assert selectors=='zeroinitializer' or (selectors.startswith('<i32 ') and all(0<=int(x)<int(shuffle[1]) for x in re.findall(r'i32 (-?\d+)',selectors))),line
	return count


def audit(build,out):
	rows = []
	for name in FIXTURES+['shift-trap']:
		source = ROOT/f'tests/bit/fixtures/bit-{name}.astra'
		options = bindings() if name=='ownership' else []
		stages = {stage: run([build/'astrac','--dump-'+stage,source,*(options if stage!='syntax' else [])]) for stage in ['syntax','semantics','core','cfg','ssa','nabi','cabi','llvm']}
		llvm,ssa = stages['llvm'],stages['ssa']
		assert not re.search(r'\b(?:shl|ashr|lshr) (?:nsw|nuw|exact)\b|\b(?:poison|undef|ptrtoint|inttoptr|bitcast)\b',llvm), name
		assert not re.search(r'\b(?:alloca|load|store) <',llvm), name
		assert not re.search(r'LanePlace|lane-place|extractelement|insertelement|sext|zext|trunc',ssa), name
		counts = scalar.predecessors(llvm)
		counts['guarded_shifts'] = guarded_shifts(llvm)
		counts['vector_phis'] = len(re.findall(r' = phi <',llvm))
		counts['ssa_shifts'] = len(re.findall(r' = shift-(?:left|right-arithmetic|right-logical) ',ssa))
		if name=='values':
			assert 'vector-extract' not in ssa and 'storage' not in ssa
			assert 'vector-v4' in stages['nabi']
			for shape in ['i8','i16','i32','i1','<16 x i8>','<8 x i16>','<4 x i32>','<8 x i1>']:
				for op in ['and','or','xor']:
					assert op+' '+shape in llvm, (op,shape)
			for shape in ['<16 x i8>','<8 x i16>','<4 x i32>']:
				for op in ['shl','ashr','lshr']:
					assert op+' '+shape in llvm
		if name=='loop':
			assert counts['vector_phis'] > 0 and counts['guarded_shifts'] >= 6
			assert re.search(r'= phi .*%v\d+\.valid',llvm), 'shift continuation must feed a phi'
		stem = out/name
		for stage,dump in stages.items():
			stem.with_suffix('.ll' if stage=='llvm' else '.'+stage).write_text(dump)
		run(['llvm-as',stem.with_suffix('.ll'),'-o',stem.with_suffix('.bc')])
		run(['opt','-passes=verify','-disable-output',stem.with_suffix('.bc')])
		run(['llc','-O0','-filetype=obj','-relocation-model=pic',stem.with_suffix('.bc'),'-o',stem.with_suffix('.o')])
		machine = run(['objdump','-dr',stem.with_suffix('.o')])
		stem.with_suffix('.machine').write_text(machine)
		stem.with_suffix('.symbols').write_text(run(['nm','-a',stem.with_suffix('.o')]))
		stem.with_suffix('.elf').write_text(run(['readelf','-aW',stem.with_suffix('.o')]))
		undefined = run(['nm','-u',stem.with_suffix('.o')])
		assert all('astra_test_resource_' in line or '_GLOBAL_OFFSET_TABLE_' in line for line in undefined.splitlines()), (name,undefined)
		if name!='shift-trap':
			linked=run(['ldd',build/'tests/bit/execution'/name])
			stem.with_suffix('.ldd').write_text(linked)
			assert not any(word in linked.lower() for word in ['glib','gobject','llvm'])
			# Expose parameter-driven functions in an audit copy; no C vector
			# signature is involved in the exact fastcc no-argument main wrapper.
		visible = re.sub(r'^define internal fastcc ', 'define fastcc ', llvm, flags=re.M)
		main_id = re.search(r'\(function #(\d+) "main" -> int',ssa)[1]
		visible += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		public = out/(name+'-audit-input.ll')
		public.write_text(visible)
		optimized = out/(name+'-O2.ll')
		run(['opt','-passes=default<O2>','-S',public,'-o',optimized])
		counts['optimized_unselected_poison_lines'] = optimized_poison(optimized.read_text())
		obj=out/(name+'-O2.o')
		run(['llc','-O2','-filetype=obj','-relocation-model=pic',optimized,'-o',obj])
		(out/(name+'-O2.machine')).write_text(run(['objdump','-dr',obj]))
		exe=out/(name+'-O2')
		run(['cc',obj,*([build/'tests/cabi/companion.o'] if name=='ownership' else []),'-o',exe])
		r=subprocess.run([exe],capture_output=True)
		assert (r.returncode < 0 if name=='shift-trap' else r.returncode==0) and r.stdout==r.stderr==b'', (name,r)
		rows.append({'fixture':name,**counts})
		# Every other pre-existing golden remains byte-identical. Only these two
		# obsolete rejection goldens are removed because eager bool is now valid.
	retired={'tests/shortcircuit/fixtures/single-and.stderr','tests/shortcircuit/fixtures/single-or.stderr'}
	goldens=0
	for path in run(['git','ls-tree','-r','--name-only',BASELINE,'tests']).splitlines():
		if Path(path).suffix not in {'.syntax','.semantics','.core','.cfg','.ssa','.nabi','.cabi','.ll','.stderr'}:
			continue
		if path in retired:
			assert not (ROOT/path).exists()
			continue
		before=subprocess.run(['git','show',BASELINE+':'+path],cwd=ROOT,capture_output=True,check=True).stdout
		assert (ROOT/path).read_bytes()==before,path
		goldens+=1
	for path in ['bootstrap/nabi','bootstrap/cabi','bootstrap/vapi','bootstrap/foreign','bootstrap/semantic/types.vala','bootstrap/semantic/int-value.vala','bootstrap/semantic/f32-value.vala','bootstrap/semantic/integer-conversion.vala','bootstrap/semantic/vector-primitives.vala','bootstrap/semantic/vector-dsp.vala','bootstrap/semantic/vector-dot.vala','bootstrap/cfg/predecessors.vala','bootstrap/ssa/dominance.vala','bootstrap/backend/llvm/llvm-target-machine.vala']:
		assert run(['git','diff',BASELINE,'--',path])=='',path
	for directory in ['semantic','core','cfg','ssa','nabi']:
		for path in (ROOT/'bootstrap'/directory).glob('*.vala'):
			code=re.sub(r'/\*.*?\*/|//[^\n]*','',path.read_text(),flags=re.S)
			assert not re.search(r'\bLLVM\w*|Astra\.Backend|CApi\.|LanePlace',code),path
	commands=json.loads((build/'compile_commands.json').read_text())
	generated=[row for row in commands if row['file'].endswith('.c') and 'meson-generated' in row['command']]
	assert generated and all('-DVALA_STRICT_C' in row['command'] and '-Werror' in row['command'] for row in generated)
	tests=[json.loads(line) for line in (build/'meson-logs/testlog.json').read_text().splitlines()]
	assert len(tests)==len(json.loads((build/'meson-info/intro-tests.json').read_text()))
	assert all(test['result']=='OK' for test in tests)
	names=[test['name'].split(':')[-1] for test in tests]
	tap=[test for test in tests if re.search(r'^1\.\.\d+',test.get('stdout',''),re.M)]
	summary={'meson_tests':len(tests),'tap_suites':len(tap),'tap_cases':sum(int(re.search(r'^1\.\.(\d+)',test['stdout'],re.M)[1]) for test in tap),'bit_tests':sum(name.startswith('bit-') for name in names),'firewalls':sum(name.endswith('-no-llvm') for name in names),'llvm_linkage':sum(name.endswith('-links-qualified-llvm') for name in names),'negative_firewalls':sum(name in ['firewall-rejects-llvm-backend','llvm-linkage-rejects-frontend'] for name in names)}
	(out/'test-results.json').write_text(json.dumps(summary,indent='\t')+'\n')
	result={'baseline':BASELINE,'workloads':rows,'baseline_goldens_unchanged':goldens,'retired_error_goldens':sorted(retired),'strict_generated_c_commands':len(generated),'nabi_cabi_vapi_unchanged':True,'upstream_llvm_free':True,'llvm':run(['llvm-config','--version']).strip(),'host':run(['uname','-m']).strip(),'source_shift_flags_absent':True,'O2_runtime_including_trap':True}
	(out/'audit-results.json').write_text(json.dumps(result,indent='\t')+'\n')
	print(json.dumps(result),flush=True)


def memory(build,out):
	logs=out/'valgrind'
	logs.mkdir(exist_ok=True)
	selected={'bit-integer-oracle-standalone','bit-semantic-standalone','bit-core-standalone','bit-cfg-standalone','bit-ssa-standalone','bit-pipeline','bit-llvm','frontend','short-circuit','vec-nabi-standalone','cabi-standalone','vapi','semantic','core','cfg'}
	jobs=[]
	for test in json.loads((build/'meson-info/intro-tests.json').read_text()):
		if test['name'] in selected:
			jobs.append((test['name'],test['cmd'],test['workdir'] or str(build),dict(os.environ,**test['env'])))
	runtime=FIXTURES+['exhaustive','matrices','trap-i8-False-int--1-left','trap-u8-False-u32-4294967295-right','trap-i16-True-int-16-right','trap-u32-True-int-32-left','trap-effects-scalar','trap-effects-vector']
	for name in runtime:
		jobs.append(('run-'+name,[str(build/'tests/bit/execution'/name)],str(ROOT),dict(os.environ)))
	for name in FIXTURES+['shift-trap']:
		options=[*bindings(),'--link-object',build/'tests/cabi/companion.o'] if name=='ownership' else []
		jobs.append(('compile-'+name,[str(build/'astrac'),str(ROOT/f'tests/bit/fixtures/bit-{name}.astra'),*map(str,options),'-o',str(logs/name)],str(ROOT),dict(os.environ)))
	for stage in ['syntax','semantics','core','cfg','ssa','nabi','cabi','llvm']:
		jobs.append(('dump-'+stage,[str(build/'astrac'),'--dump-'+stage,str(ROOT/'tests/bit/fixtures/bit-values.astra')],str(ROOT),dict(os.environ)))
	flags=['--vgdb=no','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99']
	def measure(job):
		name,argv,cwd,env=job
		command=['valgrind',*flags,'--log-file='+str(logs/(name+'.log')),*argv]
		r=subprocess.run(command,cwd=cwd,env=env,capture_output=True,text=True)
		(logs/(name+'.stdout')).write_text(r.stdout)
		(logs/(name+'.stderr')).write_text(r.stderr)
		text=(logs/(name+'.log')).read_text()
		assert 'ERROR SUMMARY:' in text,name
		def number(pattern):
			m=re.search(pattern,text)
			return int(m[1].replace(',','')) if m else 0
		return {'name':name,'command':command,'exit':r.returncode,'errors':number(r'ERROR SUMMARY: ([\d,]+) errors'),'definite':number(r'definitely lost: ([\d,]+) bytes'),'indirect':number(r'indirectly lost: ([\d,]+) bytes'),'possible':number(r'possibly lost: ([\d,]+) bytes'),'reachable':number(r'still reachable: ([\d,]+) bytes')}
	rows=[]
	with ThreadPoolExecutor(max_workers=4) as pool:
		for future in as_completed([pool.submit(measure,job) for job in jobs]):
			row=future.result()
			rows.append(row)
			(logs/'results.json').write_text(json.dumps(sorted(rows,key=lambda x:x['name']),indent='\t')+'\n')
			print(json.dumps({k:v for k,v in row.items() if k!='command'}),flush=True)
	assert len(rows)==len(jobs)
	(logs/'completion.json').write_text(json.dumps({'measured':len(rows)},indent='\t')+'\n')


if __name__=='__main__':
	parser=argparse.ArgumentParser()
	parser.add_argument('build',type=Path)
	parser.add_argument('--memory',action='store_true')
	args=parser.parse_args()
	build=args.build.resolve()
	out=build/'qualification-bit'
	out.mkdir(exist_ok=True)
	(memory if args.memory else audit)(build,out)
