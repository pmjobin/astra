# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact-baseline objects, dependency attribution, and unsuppressed memory audit."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse
import json
import os
import re
import subprocess
import sys
sys.dont_write_bytecode = True
from qualify import ROOT, LIB, HERE, STAGES, COMMANDS, run, process, sha, object_file, ordinal, cc


def objects(build, baseline, out):
	out.mkdir(parents=True, exist_ok=True)
	free = out / 'text-free.astra'; free.write_text('int main(){return 0;}')
	native = out / 'native-only.astra'; native.write_text('int measure(string x){return x.byte_length;} int main(){if(measure("a\\0é")!=4){return 1;}return 0;}')
	combined = out / 'combined.astra'; combined.write_text('extern(C) f64 text_io_math_input();\n'+(ROOT / 'examples/text-output/main.astra').read_text().replace('var label =', 'assert_code(sqrt_f64(text_io_math_input())>1.0d,746);\n\tvar label ='))
	math_input = out/'math-input.c'; math_input.write_text('double text_io_math_input(void) { volatile double input = 2.0; return input; }\n'); cc('gcc',math_input,out/'math-input.o')
	configs = {
		'text-free': ([free], [], []),
		'native-only': ([native], [], []),
		'pure-reader': ([HERE / 'fixtures/pure-reader.astra'], [], [out/'pure-reader-gcc.o']),
		'output': ([ROOT/'examples/text-output/hello.astra', LIB/'hosted/text.astra'], [], [build/'lib/astra/text-posix.o']),
		'combined': ([combined, ROOT/'examples/text-output/labels.astra', ROOT/'examples/text-output/model.astra', LIB/'hosted/text.astra', LIB/'base/contracts.astra'], ['--vapi', LIB/'hosted/math.vapi'], [build/'lib/astra/text-posix.o', build/'lib/astra/failure-trap.o', out/'math-input.o', '-lm'])
	}
	for host in ['gcc','clang']:
		cc(host, HERE/'pure-reader.c', out/('pure-reader-'+host+'.o'), ['-ffreestanding','-fno-builtin','-fno-stack-protector'])
		cc(host, LIB/'platform/text-posix.c', out/('provider-'+host+'.o'))
		assert run(['nm','-u',out/('pure-reader-'+host+'.o')]) == b''
	for host in ['gcc','clang']:
		exe = out/('pure-reader-cli-'+host); run([build/'astrac',HERE/'fixtures/pure-reader.astra','--link-object',out/('pure-reader-'+host+'.o'),'-o',exe]); assert run([exe]) == b''
	start = out/'start.o'; cc('gcc', ROOT/'tests/baselib/fixtures/start.S', start)
	records = []; comparison_count = 0
	for name,(sources,extra,links) in configs.items():
		ir = run([build/'astrac','--dump-llvm',*sources,*extra]); main = ordinal(build/'astrac',sources,'main',extra)
		ir += f'\ndefine i32 @main() {{\n\t%r = call fastcc i32 @astra.fn.{main}()\n\tret i32 %r\n}}\n'.encode()
		cabi=run([build/'astrac','--dump-cabi',*sources,*extra]); nabi=run([build/'astrac','--dump-nabi',*sources,*extra])
		if name in ['text-free','native-only']:
			for stage in ['syntax',*STAGES]:
				assert run([build/'astrac','--dump-'+stage,*sources]) == run([baseline/'astrac','--dump-'+stage,*sources]); comparison_count += 1
			assert cabi == b'(c-abi scalar-v0)\n'
		for mode in ['O0','O2','fma','preserved']:
			stem=out/(name+'-'+mode); obj=object_file(ir,stem,mode); undefined=run(['nm','-u',obj]).decode()
			if name in ['text-free','native-only']:
				baseline_ir=run([baseline/'astrac','--dump-llvm',*sources])+ir[ir.index(b'\ndefine i32 @main()'):]
				control=object_file(baseline_ir,out/('baseline-'+name+'-'+mode),mode); assert obj.read_bytes()==control.read_bytes() and undefined==''; comparison_count += 1
			if name=='pure-reader':
				assert {line.split()[-1] for line in undefined.splitlines()}=={'bounded_sum'}
				assert b'astra_host_text_write' not in ir and not re.search(rb'\b(strlen|strcmp|malloc|calloc|free|memcpy|memmove)\b',ir)
			if name=='output':
				assert {line.split()[-1] for line in undefined.splitlines()}=={'astra_host_text_write'}
			if name=='combined':
				assert all(symbol in undefined for symbol in ['astra_host_text_write','astra_base_fail','calloc','free','sqrt'])
			run(['gcc',obj,*links,'-o',stem]); p=process([stem]); assert p.returncode==0
			dependencies=run(['ldd',stem]).decode(); assert not re.search(r'lib(?:glib|gobject|LLVM)',dependencies)
			if name in ['text-free','native-only','pure-reader']:
				for host in (['gcc','clang'] if name=='pure-reader' else ['gcc']):
					exe=out/(name+'-'+mode+'-startup-'+host); companions=[out/('pure-reader-'+host+'.o')] if name=='pure-reader' else []
					run(['gcc','-nostdlib','-static','-Wl,-e,_start',start,obj,*companions,'-o',exe]); assert run(['nm','-u',exe])==b'' and run([exe])==b'' and b'NEEDED' not in run(['readelf','-d',exe])
			disassembly=run(['objdump','-dr',obj]); (out/(stem.name+'.machine.txt')).write_bytes(disassembly)
			records.append(dict(case=name,mode=mode,sha256=sha(obj.read_bytes()),object_bytes=obj.stat().st_size,undefined=undefined,linked_undefined=run(['nm','-u',stem]).decode(),dependencies=dependencies,sizes=run(['size','-A',obj]).decode(),cabi=cabi.decode(),nabi=nabi.decode(),machine_sha256=sha(disassembly)))
	providers=[]
	for host in ['gcc','clang']:
		obj=out/('provider-'+host+'.o'); symbols=run(['nm','-u',obj]).decode(); assert {line.split()[-1] for line in symbols.splitlines()}=={'write','__errno_location'}
		providers.append(dict(compiler=host,object_bytes=obj.stat().st_size,sha256=sha(obj.read_bytes()),undefined=symbols,sizes=run(['size','-A',obj]).decode()))
	result=dict(comparisons=comparison_count,objects=records,providers=providers)
	(out/'objects.json').write_text(json.dumps(result,indent='\t')+'\n'); return result


def memory(build, baseline, out, installation):
	out.mkdir(parents=True,exist_ok=True); qualified=build/'text-io-1/qualification'; jobs=[]
	for stage in ['frontend','pipeline','llvm','core','cfg','ssa','cabi']:
		jobs.append(('witness-'+stage,[build/'tests/text-io'/('astra-text-io-'+stage),'--tap'],0,'normal',False))
	jobs.append(('decoder',[build/'tests/text/astra-text-decoder','--tap'],0,'normal',False))
	for stage in ['syntax',*STAGES]:
		jobs.append(('compiler-'+stage,[build/'astrac','--dump-'+stage,HERE/'fixtures/pipeline.astra'],0,'normal',False))
	for mode in ['O0','O2','fma','preserved']:
		for host in ['gcc','clang']:
			jobs.append(('reader-'+mode+'-'+host,[qualified/('native-'+mode+'-'+host)],0,'normal',False))
	jobs += [('output',[qualified/'output'],0,'normal',False),('composition',[qualified/'composition-0'],0,'normal',False),('ordinary-false',[qualified/'failure'],0,'ordinary-false',True),('intercept-false',[qualified/'intercept-gcc',1,5,1,0,2,-1,3,0],0,'ordinary-false',False),('producer-trap',[qualified/'order-first-O0'],None,'intentional-fatal',False)]
	installed=json.loads(installation.read_text()); jobs += [('relocated-consumer',[installed['consumer']],0,'normal',False),('relocated-compiler',[installed['compiler'],'--dump-llvm',HERE/'fixtures/pipeline.astra'],0,'normal',False)]
	for label,text in [('bad-mode','[CCode(text_abi="bad")] extern(C) int f(borrowed string x);'),('bad-escape','[CCode(text_abi="utf8-i32\\0")] extern(C) int f(borrowed string x);'),('borrow-escape','[CCode(text_abi="utf8-i32")] extern(C) int f(borrowed string x); string g(string x){f(x);return x;}')]:
		path=out/(label+'.astra');path.write_text(text);jobs.append((label,[build/'astrac','--check',path],1,'normal',False))
	control=out/'ordinary-name-control.astra';control.write_text('int f(){'+''.join('int C%d=0;'%n for n in range(5001))+'return 0;}')
	jobs += [('baseline-name-control',[baseline/'astrac','--dump-semantics',control],99,'inherited-glib',False),('candidate-name-control',[build/'astrac','--dump-semantics',control],99,'inherited-glib',False)]
	# Many unique text leaves in a single block, independently of name-table growth.
	growth=out/'payload-growth.astra'; growth.write_text('[CCode(text_abi="utf8-i32")] extern(C) int f(borrowed string x); int main(){'+''.join('f("payload-%04d\\0tail");'%i for i in range(1200))+'return 0;}')
	jobs.append(('payload-growth',[build/'astrac','--dump-llvm',growth],0,'normal',False))
	def measure(job):
		name,args,status,category,fail=job; log=out/(name+'.log')
		command=['valgrind','--vgdb=no','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99','--log-file='+str(log),*map(str,args)]
		if fail:
			with open('/dev/full','wb') as full: p=subprocess.run(command,stdout=full,stderr=subprocess.PIPE,timeout=300,cwd=ROOT)
		else: p=process(command,timeout=600,cwd=ROOT)
		text=log.read_text(); assert 'ERROR SUMMARY:' in text
		def number(pattern):
			match=re.search(pattern,text);return int(match[1].replace(',','')) if match else 0
		row=dict(name=name,category=category,status=p.returncode,errors=number(r'ERROR SUMMARY: ([\d,]+) errors'),definite=number(r'definitely lost: ([\d,]+) bytes'),indirect=number(r'indirectly lost: ([\d,]+) bytes'),possible=number(r'possibly lost: ([\d,]+) bytes'),reachable=number(r'still reachable: ([\d,]+) bytes'),suppressed=number(r'suppressed: ([\d,]+) bytes'),allocations=number(r'total heap usage: ([\d,]+) allocs'))
		(out/(name+'.stderr')).write_bytes(p.stderr); assert row['suppressed']==0
		if category=='inherited-glib':
			assert row['errors']==2 and row['definite']==49152 and row['indirect']==row['possible']==0 and 'g_quark_from_string' in text and 'call_init' in text,row
		else: assert row['errors']==row['definite']==row['indirect']==row['possible']==0,row
		assert p.returncode<0 if category=='intentional-fatal' else p.returncode==status,row
		return row
	with ThreadPoolExecutor(max_workers=3) as pool: rows=list(pool.map(measure,jobs))
	(out/'memory.json').write_text(json.dumps(rows,indent='\t')+'\n');return rows


def main():
	p=argparse.ArgumentParser();p.add_argument('build',type=Path);p.add_argument('baseline',type=Path);p.add_argument('out',type=Path);p.add_argument('--memory',action='store_true');p.add_argument('--installation',type=Path);args=p.parse_args()
	build=args.build.resolve();baseline=args.baseline.resolve();out=args.out.resolve()
	if args.memory: memory(build,baseline,out,args.installation.resolve())
	else: objects(build,baseline,out)
	print('TEXT-IO audit PASS')


if __name__=='__main__': main()
