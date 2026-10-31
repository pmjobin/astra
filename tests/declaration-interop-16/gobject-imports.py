#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently authored GLib provider consumed by native typed imports."""
from pathlib import Path
import hashlib,json,os,shlex,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(compiler_arg,output_arg):
	compiler=Path(compiler_arg).resolve();output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='typed-gobject-imports-',dir=output));here=Path(__file__).resolve().parent;source=here/'gobject-imports.astra';receipt=dict(scope='typed GObject import scalar/property/reference/callback/payload/object/GError prerequisites; record/GIR/signal and later M16 gates pending',compiler_sha256=sha(compiler),sources={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),source,here/'gobject-provider.h',here/'gobject-provider.c',ROOT/'lib/runtime/interop/foreign-14.c']},checks=[])
	def run(command,contains=''):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),capture_output=True,text=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1',G_DEBUG='fatal-warnings'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==0 and contains in p.stdout+p.stderr,receipt['checks'][-1];return p.stdout
	flags=['-std=gnu11','-Wall','-Wextra','-Werror','-pthread'];includes=shlex.split(run(['pkg-config','--cflags','gobject-2.0']));libs=shlex.split(run(['pkg-config','--libs','gobject-2.0']))
	for stage in ['syntax','semantics','core','cfg','ssa','nabi','cabi']:run([compiler,'--dump-'+stage,source])
	adapter=work/'adapter.c';adapter.write_text(run([compiler,'--emit-gobject-source',source]));header=work/'bridge.h';header.write_text(run([compiler,'--emit-gobject-header',source]));(work/'gobject-provider.h').write_bytes((here/'gobject-provider.h').read_bytes());receipt['generated']={p.name:sha(p) for p in [adapter,header]}
	for level in '012':
		obj=work/('native-O'+level+'.o');run([compiler,'-O'+level,'-c',source,'-o',obj])
		for bridge_level in ('1' if level=='1' else '02'):
			client=work/('native'+level+'-bridge'+bridge_level);run(['cc',*flags,'-O'+bridge_level,*includes,'-I'+str(work),adapter,here/'gobject-provider.c',ROOT/'lib/runtime/interop/foreign-14.c',obj,*libs,'-o',client]);run([client],contains='PASS typed GObject imported methods, properties, BOOL32, references and GError retirement');receipt.setdefault('products',{})[client.name]=sha(client)
			if (level,bridge_level) in [('0','0'),('2','2')]:run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',client],contains='ERROR SUMMARY: 0 errors')
	receipt['status']='TYPED_GOBJECT_IMPORT_SCALAR_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))
if __name__=='__main__':main(*sys.argv[1:])
