#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Cross-build typed inherited COM imports against independently authored interfaces."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parents[2]


def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser=argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler',type=Path,required=True)
	parser.add_argument('--cc',type=Path,required=True)
	parser.add_argument('--cxx',type=Path,required=True)
	parser.add_argument('--sysroot',type=Path,required=True)
	parser.add_argument('--output',type=Path,required=True)
	parser.add_argument('--source',type=Path)
	parser.add_argument('--client',type=Path)
	parser.add_argument('--label',default='com-import')
	parser.add_argument('--pass-marker',default='PASS typed COM imports, inherited slots, BOOL32 callbacks and exact foreign references')
	parser.add_argument('--observe-task-free',action='store_true')
	args=parser.parse_args();compiler=args.compiler.resolve();output=args.output.resolve();assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='typed-com-imports-',dir=output));media=work/'media';media.mkdir();here=Path(__file__).resolve().parent
	source=args.source.resolve() if args.source else here/'com-imports.astra';client=args.client.resolve() if args.client else here/'com-imports-provider.cpp'
	receipt=dict(scope='typed COM scalar/property/callback import prerequisites; COM export and remaining required channels/gates pending; native Windows execution required',compiler_sha256=sha(compiler),recipe_sha256=sha(Path(__file__)),sources={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),source,client,ROOT/'lib/runtime/interop/foreign-14.c']},checks=[],products={},execution_expectations={})
	def run(command):
		assert sha(compiler)==receipt['compiler_sha256'];p=subprocess.run(list(map(str,command)),capture_output=True,text=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1'))
		receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));(work/'build.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==0,receipt['checks'][-1];return p.stdout
	target=['--target=x86_64-w64-windows-gnu'];flags=['--sysroot='+str(args.sysroot.resolve())];strict=['-std=c++17','-Wall','-Wextra','-Werror','-pedantic','-fno-exceptions','-fno-rtti']
	receipt['toolchain']=run([args.cxx,'--version']);objdump=run([args.cxx,'-print-prog-name=objdump']).strip()
	for stage in ['syntax','semantics','core','cfg','ssa','nabi','cabi']:run([compiler,*target,'--dump-'+stage,source])
	adapter=work/'adapter.cpp';adapter.write_text(run([compiler,*target,'--emit-com-source',source]));header=work/'com16.hpp';header.write_text(run([compiler,*target,'--emit-com-header',source]));assert 'reinterpret_cast' not in adapter.read_text()
	probe=work/'header.cpp';probe.write_text('#include "com16.hpp"\n#include "com16.hpp"\n');run([args.cxx,*flags,*strict,'-fsyntax-only',probe])
	forwarder=work/'records.c';forwarder.write_text(run([compiler,*target,'--emit-class-source',source]));forward_obj=work/'records.o';run([args.cc,*flags,'-std=c11','-O2','-Wall','-Wextra','-Werror','-pedantic','-c',forwarder,'-o',forward_obj])
	# Observe each matching COM allocator release, then call the real SDK free.
	# The provider and production generator contain no replacement allocator.
	allocation_probe=work/'allocation-probe.hpp';allocation_probe.write_text('#include <objbase.h>\nextern "C" void com16_task_free(void *);\n#define CoTaskMemFree com16_task_free\n')
	runtime=work/'foreign.o';run([args.cc,*flags,'-std=c11','-O2','-Wall','-Wextra','-Werror','-pedantic','-c',ROOT/'lib/runtime/interop/foreign-14.c','-o',runtime])
	for level in '012':
		obj=work/('native-O'+level+'.o');run([compiler,*target,'-O'+level,'-c',source,'-o',obj])
		for bridge_level in ('1' if level=='1' else '02'):
			binary=media/(args.label+'-O'+level+'-bridge-O'+bridge_level+'.exe')
			bridge=work/('bridge-O'+bridge_level+'.o');run([args.cxx,*flags,*strict,'-O'+bridge_level,*(['-include',allocation_probe] if args.observe_task_free or not args.source else []),'-c',adapter,'-o',bridge])
			run([args.cxx,*flags,*strict,'-O'+bridge_level,'-static','-Wl,--no-insert-timestamp',client,bridge,obj,runtime,forward_obj,'-lole32','-luuid','-o',binary])
			imports=run([objdump,'-p',binary]);deps=[line.split(':',1)[1].strip().lower() for line in imports.splitlines() if 'DLL Name:' in line];assert deps and set(deps)<={'kernel32.dll','msvcrt.dll','ole32.dll'}
			receipt['products'][binary.name]=sha(binary);receipt['execution_expectations'][binary.name]=dict(pass_markers=[args.pass_marker],system_dlls=deps)
	receipt['status']='CROSS_BUILD_PASS; native Windows execution pending';(work/'build.json').write_text(json.dumps(receipt,indent=2)+'\n');print(work/'build.json')


if __name__=='__main__':main()
