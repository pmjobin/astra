#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native void Closures through typed retained GObject connections."""
from pathlib import Path
import hashlib,json,os,shlex,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main(compiler_arg,output_arg):
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='typed-retained-native-',dir=output));runtime=ROOT/'lib/runtime/interop';here=Path(__file__).resolve().parent
	receipt=dict(scope='typed retained native scalar Closures with quiescent environment retirement; companion GIR integration is separate and final M16 qualification remains pending',compiler_sha256=sha(compiler),sources={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),here/'retained-signals.astra',here/'retained-signals-client.c',runtime/'gobject-signals-16.c',runtime/'gobject-signals-16.h',runtime/'foreign-14.c']},checks=[])
	def run(command,contains=''):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),text=True,capture_output=True,cwd=work,timeout=120,env=dict(os.environ,G_DEBUG='fatal-warnings'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==0 and contains in p.stdout+p.stderr,receipt['checks'][-1];return p.stdout
	includes=shlex.split(run(['pkg-config','--cflags','gobject-2.0']));libs=shlex.split(run(['pkg-config','--libs','gobject-2.0']))
	for level in '012':
		obj=work/('native-O'+level+'.o');run([compiler,'-O'+level,'-c',here/'retained-signals.astra','-o',obj]);client=work/('client-O'+level);run(['cc','-std=gnu11','-Wall','-Wextra','-Werror','-pthread','-O'+level,*includes,'-I'+str(runtime),here/'retained-signals-client.c',runtime/'gobject-signals-16.c',runtime/'foreign-14.c',obj,*libs,'-o',client]);run([client],contains='PASS native void Closure retained')
		if level in '02':run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',client],contains='ERROR SUMMARY: 0 errors')
	fixture=(here/'retained-signals.astra').read_text()
	for index,(old,new) in enumerate([('retained_signal_register(handler,mode)','retained_register(handler,mode)'),('retained_signal_register(handler,mode)','retained_signal_register(handler,true)'),('retained_signal_register(handler,mode)','retained_signal_register(handler)'),('void received(borrowed Environment environment,int value,bool committed,f64 weight){environment.receive(value,committed,weight);}','int received(borrowed Environment environment,int value,bool committed,f64 weight){environment.receive(value,committed,weight);return 0;}')]):
		source=work/('negative'+str(index)+'.astra');assert old in fixture;source.write_text(fixture.replace(old,new));command=[compiler,'--dump-llvm',source];p=subprocess.run(list(map(str,command)),text=True,capture_output=True,cwd=work,timeout=120);receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));assert p.returncode==1 and 'error' in p.stderr and 'define ' not in p.stdout,receipt['checks'][-1]
	for selection in ['--foreign-personalities=none','--foreign-personalities=c,com','--target=x86_64-w64-windows-gnu']:
		command=[compiler,selection,'--dump-llvm',here/'retained-signals.astra'];p=subprocess.run(list(map(str,command)),text=True,capture_output=True,cwd=work,timeout=120);receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));assert p.returncode==1 and 'define ' not in p.stdout,receipt['checks'][-1]
	receipt['status']='TYPED_RETAINED_NATIVE_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))
if __name__=='__main__':main(*sys.argv[1:])
