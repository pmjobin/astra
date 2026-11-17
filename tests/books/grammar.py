#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Existing-parser goldens and independent typed-source consumer; no new parser."""
import argparse
import ast
import datetime
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('products','toolchain','link','build','runtime'): p.add_argument('--'+name,type=Path,required=True)
	p.add_argument('--preflight',action='store_true',help='Syntax dumps only; no independent consumer or memory credit')
	p.add_argument('--reuse-build',type=Path,help='Retain an earlier task-owned consumer object only after matching its complete frozen source and actual compile record')
	p.add_argument('--reuse-runtime',type=Path)
	a = p.parse_args()
	b = output_path(a.build,WORK/'build'); r = output_path(a.runtime,WORK/'runtime')
	b.mkdir(parents=True,exist_ok=False); r.mkdir(parents=True,exist_ok=False)
	(r/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	start = datetime.datetime.now(datetime.timezone.utc).isoformat()
	manifest = json.loads(Path(__file__).with_name('grammar.json').read_text())
	products = json.loads(a.products.read_text())['products']
	tools = json.loads(a.toolchain.read_text())
	assert all(sha(path)==digest for path,digest in tools['tools'].items())
	for product in products.values():
		for image in (product,product['native'],product['doc']): assert sha(image['path'])==image['sha256']
	env = dict(os.environ,PYTHONDONTWRITEBYTECODE='1',CCACHE_DISABLE='1')
	env.update({k:v for k,v in tools['environment'].items() if v is not None})
	env.pop('LD_PRELOAD',None); env.pop('VALGRIND_OPTS',None)
	assert subprocess.check_output(['llvm-config','--version'],env=env).strip()==b'23.1.4'
	write(r/'producer-inputs.json',dict(products=dict(path=str(a.products),sha256=sha(a.products)),toolchain=dict(path=str(a.toolchain),sha256=sha(a.toolchain)),link=dict(path=str(a.link),sha256=sha(a.link)),tool_files=tools['tools']))
	cases = manifest['cases']; assert len({c['path'] for c in cases})==len(cases)
	inputs = {}; snapshots = {}; commands = []; observations = []
	def snapshot(path):
		path = Path(path); assert path.is_relative_to(ROOT) and not path.is_symlink()
		name = str(path.relative_to(ROOT)); data = path.read_bytes()
		destination = r/'inputs'/name; destination.parent.mkdir(parents=True,exist_ok=True)
		destination.write_bytes(data); destination.chmod(0o444)
		inputs[name] = dict(sha256=sha(path),bytes=len(data),git_blob=subprocess.check_output(['git','hash-object','--stdin'],input=data,cwd=ROOT,text=False).decode().strip())
		snapshots[name] = destination
		return destination
	for case in cases:
		snapshot(ROOT/case['path'])
		if case.get('golden'): snapshot(ROOT/case['golden'])
	for path in (Path(__file__),Path(__file__).with_name('grammar.json'),Path(__file__).with_name('grammar-consumer.astra')): snapshot(path)
	write(r/'inputs.json',inputs)
	def run(label,argv,expected=0,memory=False,timeout=300):
		if memory: argv = ['valgrind','--default-suppressions=no','--error-exitcode=99','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all',*argv]
		result = execute(argv,r/label,expected=expected,timeout=timeout,env=env)
		commands.append(dict(label=label,argv=list(map(str,argv)),result=result,strict_memory=memory)); write(r/'commands.json',commands)
		return result,(r/label/'stdout').read_bytes(),(r/label/'stderr').read_bytes()
	for mode,product in products.items():
		for number,case in enumerate(cases):
			label = mode+'-syntax-'+str(number)
			result,out,err = run(label,[product['path'],'--dump-syntax',snapshots[case['path']]],case['exit'])
			passed = result['status']=='EXPECTED_OUTCOME'
			if case['exit'] != 0: passed = passed and out==b''
			if case.get('golden'): passed = passed and out==snapshots[case['golden']].read_bytes()
			if case.get('diagnostic'): passed = passed and case['diagnostic'].encode() in err
			observations.append(dict(path=case['path'],host=mode,passed=passed,expected_exit=case['exit'],result=result,diagnostic=err.decode(errors='replace')))
		write(r/'observations.json',observations)
	failed = [row for row in observations if not row['passed']]
	if a.preflight or failed:
		write(r/'result.json',dict(status='GRAMMAR_DUMP_PREFLIGHT_PASS' if not failed else 'GRAMMAR_DUMP_FAILURE',start_UTC=start,completed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),cases=len(cases),observations_sha256=sha(r/'observations.json'),inputs_sha256=sha(r/'inputs.json'),failures=failed,scope='Actual current parser syntax dumps. No native language support or typed-family completeness inferred.'))
		print('Grammar dump checks:',len(observations),'failures:',len(failed))
		assert not failed
		return
		# Compile the actual current syntax source and a small independent consumer.
		# Immutable C arrays are byte transport, with no lexer or language decisions.
	provider = b/'fixtures.c'
	lines = ['#include <stdio.h>','#include <stdlib.h>']
	for i,case in enumerate(cases):
		data = snapshots[case['path']].read_bytes()
		lines.append('static const unsigned char s'+str(i)+'[]={'+','.join(map(str,data or b'\0'))+'};')
	lines += ['static const unsigned char *sources[]={'+','.join('s'+str(i) for i in range(len(cases)))+'};','static const int sizes[]={'+','.join(str(inputs[c['path']]['bytes']) for c in cases)+'};','static const int expected[]={'+','.join(str(c['exit']) for c in cases)+'};','static int seen[101], case_seen[101], current_case;','int grammar_count(void){return '+str(len(cases))+';}','int grammar_size(int n){if(n<0 || n>=grammar_count()) abort();return sizes[n];}','int grammar_byte(int n,int at){if(n<0 || n>=grammar_count() || at<0 || at>=sizes[n]) abort();return sources[n][at];}','int grammar_observe(int n,int failed){current_case=n;for(int i=1;i<=100;++i) case_seen[i]=0;printf("CASE %d %d\\n",n,failed);return failed==expected[n];}','void grammar_mark(int kind){if(kind<1 || kind>100) abort();if(!case_seen[kind]) printf("FAMILY %d %d\\n",current_case,kind);case_seen[kind]=1;seen[kind]=1;}','void grammar_finish(void){for(int i=1;i<=100;++i) if(seen[i]) printf("KIND %d\\n",i);}']
	provider.write_text('\n'.join(lines)+'\n')
	obj = b/'fixtures.o'; result,_,_ = run('fixture-provider',['cc','-std=c11','-O2','-Wall','-Wextra','-Werror','-c',provider,'-o',obj]); assert result['status']=='EXPECTED_OUTCOME'
	model = ast.parse((ROOT/'tests/selfhost-typecore/build.py').read_text())
	libraries = next(ast.literal_eval(n.value) for n in model.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='LIBRARIES' for t in n.targets))
	sources = [*sorted((ROOT/'compiler/source').glob('*.astra')),*sorted((ROOT/'compiler/syntax').glob('*.astra')),ROOT/'tests/books/grammar-consumer.astra',*[ROOT/('lib/astra/'+n+'.astra') for n in libraries]]
	actual = [snapshots.get(str(path.relative_to(ROOT))) or snapshot(path) for path in sources]
	providers = {p:h for p,h in json.loads(a.link.read_text())['objects'].items() if Path(p).name not in ('llvm-capi.o','arguments.o')}
	assert all(sha(path)==digest for path,digest in providers.items())
	write(r/'inputs.json',inputs)
	consumer_products = {}; reuse = []
	for mode in ('O0','O2'):
		output = b/('consumer-'+mode+'.o'); executable = b/('consumer-'+mode)
		old_object = None
		if a.reuse_build:
			assert a.reuse_runtime
			old_build = output_path(a.reuse_build,WORK/'build'); old_runtime = output_path(a.reuse_runtime,WORK/'runtime')
			candidate = old_build/('consumer-'+mode+'.o')
			if candidate.is_file():
				old_commands = json.loads((old_runtime/'commands.json').read_text())
				old_inputs = json.loads((old_runtime/'inputs.json').read_text())
				compile_record = next(row for row in old_commands if row['label']==mode+'-consumer-compile')
				assert compile_record['result']['status']=='EXPECTED_OUTCOME' and not compile_record['result']['timed_out']
				argv = compile_record['argv']; assert argv[:4]==[products['O2']['path'],'-c','-'+mode,'-o'] and Path(argv[4])==candidate
				current_names = [str(path.relative_to(r/'inputs')) for path in actual]
				old_names = [str(Path(path).relative_to(old_runtime/'inputs')) for path in argv[5:]]
				assert current_names==old_names
				for name in old_names:
					assert old_inputs[name]['sha256']==inputs[name]['sha256']==sha(old_runtime/'inputs'/name)
				assert sha(old_runtime/'executed-recipe.py.txt')==old_inputs['tests/books/grammar.py']['sha256']
				shutil.copyfile(candidate,output); assert sha(candidate)==sha(output)
				reuse.append(dict(profile=mode,object_path=str(candidate),object_sha256=sha(candidate),observed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),compile_record=compile_record,old_inputs_sha256=sha(old_runtime/'inputs.json'),scope='Retained actual compile over identical complete frozen syntax/consumer/library sources. Object bytes authenticated now, not backdated. Fresh provider/link/execution and strict memory follow.'))
				write(r/'object-reuse.json',reuse); old_object = candidate
		if old_object is None:
			result,_,_ = run(mode+'-consumer-compile',[products['O2']['path'],'-c','-'+mode,'-o',output,*actual],timeout=7200); assert result['status']=='EXPECTED_OUTCOME'
		consumer_products[mode] = dict(object=dict(path=str(output),sha256=sha(output)),compiled_now=old_object is None)
		write(r/'consumer-products.json',consumer_products)
		result,_,_ = run(mode+'-consumer-link',['cc','-no-pie',output,obj,*providers,'-o',executable]); assert result['status']=='EXPECTED_OUTCOME'
		consumer_products[mode]['executable'] = dict(path=str(executable),sha256=sha(executable)); write(r/'consumer-products.json',consumer_products)
		result,out,_ = run(mode+'-consumer-memory',[executable],42,memory=True,timeout=1800); assert result['status']=='EXPECTED_OUTCOME'
		assert all(marker in (r/(mode+'-consumer-memory/stderr')).read_bytes() for marker in (b'ERROR SUMMARY: 0 errors',b'in use at exit: 0 bytes in 0 blocks',b'(suppressed: 0 from 0)'))
		assert [(int(i),int(v)) for i,v in re.findall(rb'(?m)^CASE (\d+) (\d+)$',out)]==[(i,c['exit']) for i,c in enumerate(cases)]
		observed = sorted(int(v) for v in re.findall(rb'(?m)^KIND (\d+)$',out))
		by_case = {case['path']:[] for case in cases}
		for item,code in re.findall(rb'(?m)^FAMILY (\d+) (\d+)$',out): by_case[cases[int(item)]['path']].append(int(code))
		write(r/(mode+'-families.json'),dict(observed_codes=observed,case_codes=by_case,product=dict(path=str(executable),sha256=sha(executable))))
	first = json.loads((r/'O0-families.json').read_text())['observed_codes']; assert first==json.loads((r/'O2-families.json').read_text())['observed_codes']
	assert json.loads((r/'O0-families.json').read_text())['case_codes']==json.loads((r/'O2-families.json').read_text())['case_codes']
	kinds = json.loads((ROOT/'docs/books/inventory.json').read_text())['syntax_families']
	missing = [row['name'] for code,row in enumerate(kinds,1) if not row['abstract'] and code not in first]
	assert all(sha(ROOT/name)==row['sha256'] for name,row in inputs.items())
	write(r/'result.json',dict(status='CURRENT_PARSER_GOLDENS_AND_TYPED_SOURCE_O0_O2_PASS',start_UTC=start,completed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(),cases=len(cases),protected_goldens=sum(bool(c.get('golden')) for c in cases),host_profiles=['O0','O2'],typed_consumer_profiles=['O0','O2'],observed_families=[kinds[i-1]['name'] for i in first],unobserved_concrete_families=missing,inputs_sha256=sha(r/'inputs.json'),commands_sha256=sha(r/'commands.json'),scope='Existing parser, independently expected acceptance and protected dump goldens. Actual current typed-source consumer at O0/O2 with strict returning memory. Missing concrete families remain open; parsing establishes no runtime support.'))
	print('Current grammar cases:',len(cases),'observed families:',len(first),'missing concrete:',missing)


if __name__ == '__main__':
	main()
