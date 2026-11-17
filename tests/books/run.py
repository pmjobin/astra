#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Current native book examples, independent expected data and strict memory."""
import argparse
from contextlib import contextmanager
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('products','toolchain','link','build','runtime'): p.add_argument('--'+name,type=Path,required=True)
	p.add_argument('--quick',action='store_true',help='Authoring semantic preflight only; no native acceptance credit')
	p.add_argument('--case',action='append',help='Explicit case IDs for focused authoring; omission runs the entire manifest')
	p.add_argument('--keep-going',action='store_true',help='Record failed profiles and attempt the rest; failures still reject qualification')
	a = p.parse_args()
	build = output_path(a.build,WORK/'build'); runtime = output_path(a.runtime,WORK/'runtime')
	build.mkdir(parents=True,exist_ok=False); runtime.mkdir(parents=True,exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	start = datetime.datetime.now(datetime.timezone.utc).isoformat()
	manifest = json.loads(Path(__file__).with_name('examples.json').read_text())
	all_cases = manifest['cases']
	if a.case:
		assert len(a.case) == len(set(a.case)) and set(a.case) <= {row['id'] for row in all_cases}
		manifest['cases'] = [row for row in all_cases if row['id'] in a.case]
	files = {r['id']:ROOT/r['path'] for r in manifest['files']}
	products = json.loads(a.products.read_text())['products']
	assert set(products) == {'O0','O2'}
	for product in products.values():
		for image in (product,product['native'],product['doc']): assert sha(image['path']) == image['sha256']
	toolchain = json.loads(a.toolchain.read_text())
	assert all(sha(path) == digest for path,digest in toolchain['tools'].items())
	env = dict(os.environ,PYTHONDONTWRITEBYTECODE='1')
	env.update({key:value for key,value in toolchain['environment'].items() if value is not None})
	env.pop('LD_PRELOAD',None); env.pop('VALGRIND_OPTS',None)
	assert subprocess.check_output(['llvm-config','--version'],env=env).strip() == b'23.1.4'
	providers = {path:digest for path,digest in json.loads(a.link.read_text())['objects'].items() if Path(path).name not in ('llvm-capi.o','arguments.o')}
	assert all(sha(path) == digest for path,digest in providers.items())
	inputs = {str(path):sha(path) for path in (*files.values(),a.products,a.toolchain,a.link,Path(__file__).with_name('examples.json'),Path(__file__))}
	witnesses = {}
	def preserve_input(path):
		original = Path(path)
		relative = Path('repository')/original.relative_to(ROOT) if original.is_relative_to(ROOT) else Path('external')/original.relative_to(WORK)
		witness = runtime/'inputs'/relative
		witness.parent.mkdir(parents=True,exist_ok=True)
		if witness.exists(): assert witness.read_bytes() == original.read_bytes()
		else: witness.write_bytes(original.read_bytes())
		witnesses[str(original)] = str(witness.relative_to(runtime))
	for path in inputs: preserve_input(path)
	commands = []; results = []; emitted = {}; foreign_objects = {}; diagnostics = {}
	profiles = []
	@contextmanager
	def qualify_profile(label):
		try:
			yield
		except AssertionError as error:
			profiles.append(dict(label=label,passed=False,error=str(error)))
			if not a.keep_going: raise
		else:
			profiles.append(dict(label=label,passed=True))
		finally:
			write(runtime/'profiles.json',profiles)
	def run(label,argv,expected=0,memory=False):
		if memory: argv = ['valgrind','--trace-children=yes','--default-suppressions=no','--error-exitcode=99','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all',*argv]
		result = execute(argv,runtime/label,expected=expected,timeout=300,env=env)
		commands.append(dict(label=label,argv=list(map(str,argv)),result=result,strict_memory=memory))
		write(runtime/'commands.json',commands)
		if result['status'] != 'EXPECTED_OUTCOME' and not a.quick: raise AssertionError((label,(runtime/label/'stderr').read_text()))
		if memory: assert all(marker in (runtime/label/'stderr').read_bytes() for marker in (b'ERROR SUMMARY: 0 errors',b'in use at exit: 0 bytes in 0 blocks',b'(suppressed: 0 from 0)')),label
		return (runtime/label/'stdout').read_bytes(),(runtime/label/'stderr').read_bytes()
	if a.quick:
		for case in manifest['cases']:
			sources = [files[key] for key in case['files'] if files[key].suffix == '.astra']
			libraries = [ROOT/path for path in case.get('libraries',[])]
			_,err = run(case['id'],[products['O2']['path'],'--check',*sources,*libraries],1 if case['mode'] == 'compile_fail' else 0)
			passed = commands[-1]['result']['status'] == 'EXPECTED_OUTCOME'
			if case['mode'] == 'compile_fail': passed = passed and case['diagnostic'].lower().encode() in err.lower()
			results.append(dict(id=case['id'],passed=passed,stderr=err.decode()))
			print(case['id'],passed,err.decode().strip(),flush=True)
		write(runtime/'result.json',dict(status='BOOK_SEMANTIC_PREFLIGHT_PASS' if all(r['passed'] for r in results) else 'BOOK_SEMANTIC_PREFLIGHT_FAILURE',cases=results,inputs=inputs,commands_sha256=sha(runtime/'commands.json'),scope='Authoring checks only; no native execution credit.'))
		assert all(r['passed'] for r in results)
		return
	for case in manifest['cases']:
		profile_start = len(profiles)
		name = case['id']; sources = [files[key] for key in case['files'] if files[key].suffix == '.astra']
		libraries = [ROOT/path for path in case.get('libraries',[])]
		inputs.update({str(path):sha(path) for path in libraries})
		inputs.update({str(ROOT/path):sha(ROOT/path) for path in case.get('data',[])})
		inputs.update({str(ROOT/row['data']):sha(ROOT/row['data']) for row in case.get('extra_runs',[])})
		for path in inputs:
			if path not in witnesses: preserve_input(path)
		foreign = []
		if not a.quick:
			for key in case['files']:
				if files[key].suffix != '.c': continue
				if key in foreign_objects:
					foreign.append(foreign_objects[key])
					continue
				obj = build/(key+'.o')
				run(key+'-C-build',['cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',files[key],'-o',obj])
				foreign.append(obj); emitted[str(obj)] = sha(obj); foreign_objects[key] = obj
		for host_mode,product in products.items():
			if a.quick and host_mode != 'O2': continue
			compiler = product['path']
			for target_mode in (('O0',) if a.quick else ('O0','O2')):
				label = name+'-'+host_mode+'-'+target_mode
				with qualify_profile(label):
					obj = build/(label+'.o'); sentinel = b'BOOK_NEGATIVE_OUTPUT_SENTINEL\n'
					if a.quick:
						argv = [compiler,'--check',*sources,*libraries]
					else:
						argv = [compiler,'-c','-'+target_mode,'-o',obj,*sources,*libraries]
					if case['mode'] == 'compile_fail':
						obj.write_bytes(sentinel)
						_,err = run(label+'-reject',argv,1,memory=not a.quick)
						assert case['diagnostic'].lower().encode() in err.lower(),(name,err)
						assert obj.read_bytes() == sentinel
						fresh = build/(label+'-absent.o')
						fresh_argv = [compiler,'-c','-'+target_mode,'-o',fresh,*sources,*libraries]
						out,diagnostic = run(label+'-reject-absent',fresh_argv,1)
						assert not fresh.exists() and out == b''
						assert case['diagnostic'].lower().encode() in diagnostic.lower()
						if name in diagnostics: assert diagnostics[name] == diagnostic.decode(),(name,'host/target diagnostic drift')
						else: diagnostics[name] = diagnostic.decode()
						continue
					run(label+'-compile',argv,memory=not a.quick)
					if a.quick: continue
					emitted[str(obj)] = sha(obj)
					ir = build/(label+'.ll')
					run(label+'-IR',[compiler,'--emit-llvm','-'+target_mode,'-o',ir,*sources,*libraries])
					run(label+'-verify',['opt','-passes=verify','-disable-output',ir])
					emitted[str(ir)] = sha(ir)
					if case['mode'] == 'run':
						exe = build/label
						run(label+'-link',['cc','-no-pie',obj,*foreign,*(providers if libraries else []),'-o',exe])
						emitted[str(exe)] = sha(exe)
						invocation = [exe]
						if case.get('data'):
							invocation = ['env','ASTRA_READINGS_INPUT='+str(ROOT/case['data'][0]),exe]
						out,err = run(label+'-plain-execute',invocation,case['exit'])
						assert out == case.get('stdout','').encode() and err == case.get('stderr','').encode(),(label,out,err)
						out,_ = run(label+'-execute',invocation,case['exit'],memory=True)
						assert out == case.get('stdout','').encode(),(label,out)
						if case.get('data'):
							for number,path in enumerate([ROOT/case['data'][1],runtime/'absent-input.txt']):
								out,err = run(label+'-plain-input-refusal-'+str(number),['env','ASTRA_READINGS_INPUT='+str(path),exe],64)
								assert out == b'' and err == b''
								out,_ = run(label+'-input-refusal-'+str(number),['env','ASTRA_READINGS_INPUT='+str(path),exe],64,memory=True)
								assert out == b''
						for number,row in enumerate(case.get('extra_runs',[])):
							invocation = ['env','ASTRA_READINGS_INPUT='+str(ROOT/row['data']),exe]
							out,err = run(label+'-plain-extra-'+str(number),invocation,row['exit'])
							assert out == row['stdout'].encode() and err == row['stderr'].encode()
							out,_ = run(label+'-extra-'+str(number),invocation,row['exit'],memory=True)
							assert out == row['stdout'].encode()
						if case.get('freestanding'):
							startup = runtime/'start.S'
							startup.write_text('.text\n.globl _start\n_start:\n call main\n mov %eax,%edi\n mov $60,%eax\n syscall\n.section .note.GNU-stack,"",@progbits\n')
							static = build/(label+'-no-runtime')
							run(label+'-static-link',['cc','-nostdlib','-static','-no-pie','-Wl,-e,_start',startup,obj,'-o',static])
							run(label+'-static-execute',[static],case['exit'],memory=True)
							out,_ = run(label+'-undefined',['nm','-u',static]); assert not out
							out,_ = run(label+'-segments',['readelf','-l',static]); assert b'INTERP' not in out
		results.append(dict(id=name,mode=case['mode'],status='EXPECTED_OUTCOMES_PASS' if all(row['passed'] for row in profiles[profile_start:]) else 'FAILED'))
		print(name,results[-1]['status'],flush=True)
	assert all(sha(path) == digest for path,digest in {**inputs,**providers,**emitted}.items())
	write(runtime/'result.json',dict(status='BOOK_CURRENT_NATIVE_O0_O2_STRICT_MEMORY_PASS' if all(row['passed'] for row in profiles) else 'BOOK_CURRENT_NATIVE_O0_O2_STRICT_MEMORY_FAILURE',profiles=profiles,start_UTC=start,completed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),cases=results,full_manifest=not a.case,manifest_case_count=len(all_cases),products=products,inputs=inputs,input_witnesses=witnesses,build=str(build),emit_products=emitted,diagnostics=diagnostics,commands_sha256=sha(runtime/'commands.json'),LLVM='23.1.4',scope='Actual compiler host O0/O2 and target O0/O2; exact plain stdout/stderr and exits, identical complete refusal diagnostics across all four profiles, LLVM verify, absent outputs and preserved refusal sentinels, unsuppressed compiler/program memory. Explicit selections qualify only the listed cases. Quick mode is semantic authoring evidence only. Static no-runtime scope is the fixed-array program on Linux x86-64.'))

	assert all(row['passed'] for row in profiles), 'Book profiles failed; inspect profiles.json and command streams'


if __name__ == '__main__':
	main()
