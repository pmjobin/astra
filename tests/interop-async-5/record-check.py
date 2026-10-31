# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A36 public driver, separately compiled GCC/Clang providers/clients and ABI evidence."""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
APP = ROOT / 'examples/interop-async-5/record-diagnostics.astra'
EXPECTED = b'record-client: 1280 by-value roundtrips hash=6562511336861592192\n'
LAYOUT = b'RecordInts size=16 align=8 last=8\nRecordFloats size=16 align=8 last=8\nRecordMixed size=16 align=8 last=8\nRecordStack size=24 align=8 last=16\nRecordPadded size=16 align=8 last=8\n'

def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main(compiler, output):
	compiler, out = Path(compiler).resolve(), Path(output).resolve()
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	sources = [APP, Path(__file__).resolve(), *[HERE / ('record-' + name) for name in ['api.h','client.c','provider.c','reference.c','layout.c','proof.vala','loop.astra']]]
	receipt = dict(status='RUNNING', compiler_sha256=sha(compiler), sources={str(p.relative_to(ROOT)):sha(p) for p in sources}, commands=[], products={}, valgrind=0, finite_profile='GNU x86-64 SysV LP64: 1..3 64-bit numeric fields or singleton f32/padded f32,f64; at most two logical parameters')
	def save():
		(out/'results.json').write_text(json.dumps(receipt, indent=2)+'\n')
	def run(argv, code=0, stdout=b'', memory=False, diagnostic=None, stack_limit=False):
		argv=list(map(str,argv)); start=time.monotonic()
		def limit_stack(): resource.setrlimit(resource.RLIMIT_STACK,(262144,262144))
		p=subprocess.run(argv,capture_output=True,cwd=ROOT,timeout=180,env=dict(os.environ,CCACHE_DISABLE='1'),preexec_fn=limit_stack if stack_limit else None)
		good=p.returncode==code and (stdout is None or p.stdout==stdout)
		if memory:
			good &= all(x in p.stderr for x in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		elif diagnostic:
			good &= diagnostic.encode() in p.stderr
		else:
			good &= not p.stderr
		receipt['commands'].append(dict(argv=argv,exit=p.returncode,passed=bool(good),stdout_hex=p.stdout.hex(),stderr_hex=p.stderr.hex(),seconds=time.monotonic()-start,memory=memory,stack_limit_bytes=262144 if stack_limit else None))
		save()
		assert good,(argv,p.returncode,p.stdout,p.stderr)
		if memory: receipt['valgrind']+=1
		return p.stdout
	def product(path): receipt['products'][Path(path).name]=sha(path);save()
	vg=['valgrind','--default-suppressions=no','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=all','--error-exitcode=97']
	compilers=['gcc','clang-22' if shutil.which('clang-22') else 'clang']
	receipt['toolchains']={cc:dict(path=shutil.which(cc),version=run([cc,'--version'],stdout=None).decode().splitlines()[0]) for cc in compilers}
	for stage in ['semantics','core','cfg','ssa','nabi','cabi','llvm']:
		data=run([compiler,'--dump-'+stage,APP],stdout=None)
		dump=out/(stage+'.txt');dump.write_bytes(data);product(dump)
	llvm=(out/'llvm.txt').read_text()
	assert re.search(r'declare \{ i64, double \} @c_record_mixed\(i64[^,]*, double',llvm)
	assert re.search(r'declare \{ float, double \} @c_record_padded\(float[^,]*, double',llvm)
	assert re.search(r'declare void @c_record_stack\(ptr[^\n]*sret\([^\n]*byval\(',llvm)
	assert 'define internal fastcc' in llvm and 'define { i64, double } @astra_record_mixed' in llvm
	cabi=(out/'cabi.txt').read_text();assert 'pod-value-v6' in cabi and 'byval-stack' in cabi and 'sret' in cabi
	negative={
		'missing-mode':'struct R { i64 a; } extern(C) R bad(R v); int main(){return 0;}',
		'small-integers':'struct R { int a; int b; } [CCode(record_abi="value-lp64")] extern(C) R bad(R v); int main(){return 0;}',
		'nested':'struct I { i64 a; } struct R { I value; } [CCode(record_abi="value-lp64")] extern(C) R bad(R v); int main(){return 0;}',
		'pointer-field':'struct R { void* a; } [CCode(record_abi="value-lp64")] extern(C) R bad(R v); int main(){return 0;}',
		'too-large':'struct R { i64 a; i64 b; i64 c; i64 d; } [CCode(record_abi="value-lp64")] extern(C) R bad(R v); int main(){return 0;}',
		'parameter-budget':'struct R { i64 a; } [CCode(record_abi="value-lp64")] extern(C) R bad(R a,R b,R c); int main(){return 0;}',
		'borrowed-value':'struct R { i64 a; } [CCode(record_abi="value-lp64")] extern(C) R bad(borrowed R v); int main(){return 0;}',
		'unannotated-export':'struct R { i64 a; } export(C) R bad(R v){return v;} int main(){return 0;}',
		'nominal-mismatch':'struct R { i64 a; } struct S { i64 a; } [CCode(record_abi="value-lp64")] extern(C) R bad(R v); int main(){S s={a=1}; R r=bad(s);return 0;}',
	}
	for name,text in negative.items():
		source=out/(name+'.astra');source.write_text(text)
		run([compiler,'--check',source],code=1,diagnostic='error:')
	providers={}
	for cc in compilers:
		layout=out/(cc+'-layout');run([cc,'-std=c11','-Wall','-Wextra','-Werror',HERE/'record-layout.c','-o',layout]);run([layout],stdout=LAYOUT);product(layout)
		asm=out/(cc+'-provider.s');run([cc,'-std=c11','-O0','-S',HERE/'record-provider.c','-o',asm]);product(asm)
		assembly=asm.read_text();assert 'c_record_stack:' in assembly and '%xmm0' in assembly and '%rsp' in assembly
		if 'clang' in cc:
			ir=out/(cc+'-provider.ll');run([cc,'-std=c11','-O0','-S','-emit-llvm',HERE/'record-provider.c','-o',ir]);product(ir)
			data=ir.read_text();assert re.search(r'define[^\n]*\{ i64, double \} @c_record_mixed\(i64[^,]*, double',data)
			assert re.search(r'define[^\n]*void @c_record_stack\(ptr[^\n]*sret\([^\n]*byval\(',data)
			assert re.search(r'define[^\n]*\{ float, double \} @c_record_padded\(float[^,]*, double',data)
		for level in [0,1,2]:
			provider=out/f'{cc}-provider-O{level}.o';run([cc,'-std=c11','-Wall','-Wextra','-Werror',f'-O{level}','-c',HERE/'record-provider.c','-o',provider]);product(provider);providers[cc,level]=provider
			reference=out/f'{cc}-reference-O{level}';run([cc,'-std=c11','-Wall','-Wextra','-Werror',f'-O{level}',HERE/'record-client.c',HERE/'record-reference.c',provider,'-o',reference]);run([reference],stdout=EXPECTED);product(reference)
	for level in [0,1,2]:
		obj=out/f'astra-record-O{level}.o';run([compiler,f'-O{level}','-c',APP,'-o',obj]);product(obj)
		for provider_cc in compilers:
			provider=providers[provider_cc,level]
			loop=out/f'{provider_cc}-loop-O{level}';run([compiler,f'-O{level}',HERE/'record-loop.astra','--link-object',provider,'-o',loop]);run([loop],stack_limit=True);run([*vg,loop],memory=True);product(loop)
			executable=out/f'{provider_cc}-A36-O{level}';run([compiler,f'-O{level}',APP,'--link-object',provider,'-o',executable]);run([executable],stdout=b'record-diagnostics hash=1426\n');run([*vg,executable],stdout=b'record-diagnostics hash=1426\n',memory=True);product(executable)
			for client_cc in compilers:
				client=out/f'{provider_cc}-{client_cc}-client-O{level}';run([client_cc,'-std=c11','-Wall','-Wextra','-Werror',f'-O{level}',HERE/'record-client.c',provider,obj,'-o',client]);run([client],stdout=EXPECTED);run([*vg,client],stdout=EXPECTED,memory=True);product(client)
	receipt['status']='PASS';save();print('A36 C by-value record diagnostics: PASS')

if __name__=='__main__': main(*sys.argv[1:])
