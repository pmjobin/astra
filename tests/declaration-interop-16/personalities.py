#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""One unchanged Source declaration: Linux C/GLib, Windows C/COM, native only."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shlex
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--compiler',type=Path,required=True);parser.add_argument('--output',type=Path,required=True);parser.add_argument('--cc',type=Path);parser.add_argument('--cxx',type=Path);parser.add_argument('--sysroot',type=Path);args=parser.parse_args()
	compiler=args.compiler.resolve();output=args.output.resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='declared-personalities-',dir=output));here=Path(__file__).resolve().parent;source=here/'personalities.astra';windows=args.cc is not None
	selection='c,com' if windows else 'c,gobject';target=['--target=x86_64-w64-windows-gnu'] if windows else [];selected=['--foreign-personalities='+selection,*target];sources=[Path(__file__).resolve(),source,here/('personalities-client.cpp' if windows else 'personalities-client.c'),ROOT/'lib/runtime/interop/foreign-14.c']
	receipt=dict(scope='common-source explicit personality prerequisite; remaining M16 gates pending',compiler_sha256=sha(compiler),sources={str(p.relative_to(ROOT)):sha(p) for p in sources},checks=[],negative_checks=[],products={},execution_expectations={})
	def run(command,expected=0,contains='',env=None):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),capture_output=True,text=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1',G_DEBUG='fatal-warnings',**(env or {})));rows=receipt['checks' if expected==0 else 'negative_checks'];rows.append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));(work/'build.json').write_text(json.dumps(receipt,indent=2)+'\n');assert (p.returncode==0 if expected==0 else p.returncode!=0) and contains in p.stdout+p.stderr,rows[-1];return p.stdout
	for stage in ['syntax','semantics','core','cfg','ssa','nabi','cabi']:
		run([compiler,*selected,'--dump-'+stage,source],contains='class=Facet declared=c,com,gobject active='+selection)
		run([compiler,'--foreign-personalities=none',*target,'--dump-'+stage,source],contains='class=Facet declared=c,com,gobject active=none')
	run([compiler,*target,'--dump-semantics',source],expected=1,contains='explicit --foreign-personalities selection')
	for bad in ['','c,c','none,c','unknown']:
		run([compiler,'--foreign-personalities='+bad,'--dump-semantics',source],expected=1,contains='foreign')
	run([compiler,'--foreign-personalities=c,com','--dump-cabi',source],expected=1,contains='requires --target=')
	run([compiler,'--foreign-personalities=c,gobject','--target=x86_64-w64-windows-gnu','--dump-cabi',source],expected=1,contains='GObjectExport requires')
	inactive=work/'inactive.astra';inactive.write_text(source.read_text()+'\nint inactive(borrowed void* unknown){try{var facet=IFacet.init(unknown);return facet.count;}catch(Fault fault){return -1;}}\n')
	for stage in ['semantics','core','cfg','ssa','nabi','cabi']:
		run([compiler,'--foreign-personalities=none',*target,'--dump-'+stage,inactive],expected=1,contains='unselected foreign personality')
	mode='com' if windows else 'gobject';header=work/('sdk.hpp' if windows else 'sdk.h');header.write_text(run([compiler,*selected,'--emit-'+mode+'-header',source]));adapter=work/('adapter.cpp' if windows else 'adapter.c');adapter.write_text(run([compiler,*selected,'--emit-'+mode+'-source',source]));forwarder=work/'forwarder.c';forwarder.write_text(run([compiler,*selected,'--emit-class-source',source]));native_header=work/'native.h';native_header.write_text(run([compiler,*selected,'--emit-class-header',source]))
	if windows:
		assert args.cxx and args.sysroot;cc=str(args.cc);cxx=str(args.cxx);sysroot=['--sysroot='+str(args.sysroot.resolve())];includes=[];libs=['-lole32','-luuid'];media=work/'media';media.mkdir();strict=['-std=c++17','-Wall','-Wextra','-Werror','-pedantic','-fno-exceptions','-fno-rtti'];objdump=run([cxx,'-print-prog-name=objdump']).strip()
	else:
		cc='cc';cxx=cc;sysroot=[];includes=shlex.split(run(['pkg-config','--cflags','gobject-2.0']));libs=shlex.split(run(['pkg-config','--libs','gobject-2.0']));strict=['-std=gnu11','-Wall','-Wextra','-Werror','-pthread'];objdump='objdump'
	runtime=work/'foreign.o';run([cc,*sysroot,'-std=c11','-O2','-c',ROOT/'lib/runtime/interop/foreign-14.c','-o',runtime]);forward_obj=work/'forwarder.o';run([cc,*sysroot,'-std=c11','-O2','-Wall','-Wextra','-Werror','-c',forwarder,'-o',forward_obj])
	probe=work/('header.cpp' if windows else 'header.c');probe.write_text('#include "'+header.name+'"\n#include "'+header.name+'"\n');run([cxx,*sysroot,*strict,*includes,'-fsyntax-only',probe])
	for level in '012':
		obj=work/('native-O'+level+'.o');run([compiler,*selected,'-O'+level,'-c',source,'-o',obj])
		if not windows:
			none=work/('none-O'+level+'.o');run([compiler,'--foreign-personalities=none','-O'+level,'-c',source,'-o',none]);symbols=run(['nm','-u',none]);assert 'personality16_protocol' not in symbols and 'g_object' not in symbols and 'CoTask' not in symbols;defined=run(['nm','--defined-only',none]);assert 'personality16_native_create' not in defined
			client=work/('native-only-O'+level);run([cc,*strict,'-O2','-DNATIVE_ONLY',here/'personalities-client.c',none,runtime,'-o',client]);run([client],contains='PASS common declaration');dependencies=run(['ldd',client]);assert 'glib' not in dependencies and 'gobject' not in dependencies
			if level in '02':run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',client],contains='ERROR SUMMARY: 0 errors')
		for bridge_level in ('1' if level=='1' else '02'):
			bridge=work/('bridge-O'+bridge_level+'.o');run([cxx,*sysroot,*strict,*includes,'-O'+bridge_level,'-c',adapter,'-o',bridge]);client=(media/('personality-O'+level+'-bridge-O'+bridge_level+'.exe')) if windows else work/('client-O'+level+'-bridge-O'+bridge_level)
			run([cxx,*sysroot,*strict,*includes,'-O2',*(['-static','-Wl,--no-insert-timestamp'] if windows else ['-DWITH_GOBJECT']),here/('personalities-client.cpp' if windows else 'personalities-client.c'),bridge,obj,runtime,forward_obj,*libs,'-o',client])
			if windows:
				imports=run([objdump,'-p',client]);deps=[line.split(':',1)[1].strip().lower() for line in imports.splitlines() if 'DLL Name:' in line];assert deps and set(deps)<={'kernel32.dll','msvcrt.dll','ole32.dll'};receipt['products'][client.name]=sha(client);receipt['execution_expectations'][client.name]=dict(pass_markers=['PASS common declaration C and COM personalities, captured callback and exact native lifetime'],system_dlls=deps)
			else:
				run([client],contains='PASS common declaration');
				if (level,bridge_level) in [('0','0'),('2','2')]:run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',client],contains='ERROR SUMMARY: 0 errors')
	receipt['status']='CROSS_BUILD_PASS; native Windows execution pending' if windows else 'COMMON_SOURCE_LINUX_PERSONALITIES_PASS';(work/'build.json').write_text(json.dumps(receipt,indent=2)+'\n');print(work/'build.json')


if __name__=='__main__':main()
