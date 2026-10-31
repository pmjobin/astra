#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build independent Windows LLP64/IEEE/heap probes; native guest execution required."""
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
	parser.add_argument('--sysroot',type=Path,required=True)
	parser.add_argument('--output',type=Path,required=True)
	args=parser.parse_args();compiler=args.compiler.resolve();output=args.output.resolve();assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='windows-machine-',dir=output));media=work/'media';media.mkdir();here=Path(__file__).resolve().parent
	receipt=dict(scope='Windows LLP64, IEEE gradual underflow and process heap integrity; native guest execution required; heap integrity is not a leak measurement',compiler_sha256=sha(compiler),recipe_sha256=sha(Path(__file__)),sources={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),here/'windows-machine.astra',here/'windows-machine-client.c',ROOT/'lib/runtime/interop/foreign-14.c']},checks=[],products={},execution_expectations={})
	def run(command):
		assert sha(compiler)==receipt['compiler_sha256']
		p=subprocess.run(list(map(str,command)),capture_output=True,text=True,cwd=work,timeout=120,env=dict(os.environ,CCACHE_DISABLE='1'))
		receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));(work/'build.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==0,receipt['checks'][-1];return p.stdout
	flags=['--sysroot='+str(args.sysroot.resolve()),'-std=c11','-Wall','-Wextra','-Werror','-pedantic','-O2','-static','-Wl,--no-insert-timestamp']
	receipt['toolchain']=run([args.cc,'--version']);objdump=run([args.cc,'-print-prog-name=objdump']).strip()
	(work/'machine16.h').write_text(run([compiler,'--target=x86_64-w64-windows-gnu','--emit-class-header',here/'windows-machine.astra']))
	for level in '012':
		obj=work/('native-O'+level+'.o');run([compiler,'--target=x86_64-w64-windows-gnu','-O'+level,'-c',here/'windows-machine.astra','-o',obj])
		for kind in ['independent','sdk']:
			binary=media/('machine-'+kind+'-O'+level+'.exe')
			run([args.cc,*flags,*(['-DUSE_SDK'] if kind=='sdk' else []),'-I',work,here/'windows-machine-client.c',obj,ROOT/'lib/runtime/interop/foreign-14.c','-o',binary])
			imports=run([objdump,'-p',binary]);deps=[line.split(':',1)[1].strip().lower() for line in imports.splitlines() if 'DLL Name:' in line];assert deps and set(deps)<={'kernel32.dll','msvcrt.dll'}
			receipt['products'][binary.name]=sha(binary);receipt['execution_expectations'][binary.name]=dict(pass_markers=['PASS Windows LLP64 scalar ABI, gradual underflow and heap integrity'],system_dlls=deps)
	receipt['status']='CROSS_BUILD_PASS; native Windows execution pending';(work/'build.json').write_text(json.dumps(receipt,indent=2)+'\n');print(work/'build.json')


if __name__=='__main__':main()
