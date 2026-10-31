#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent GObject provider for the optional typed retained runtime protocol."""
from pathlib import Path
import hashlib,json,os,shlex,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main(output_arg):
	output=Path(output_arg).resolve();assert not output.is_relative_to(ROOT);output.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='retained-signal-runtime-',dir=output));runtime=ROOT/'lib/runtime/interop';here=Path(__file__).resolve().parent
	receipt=dict(scope='typed retained GObject runtime only; native compiler and GIR integration pending',sources={str(p.relative_to(ROOT)):sha(p) for p in [Path(__file__).resolve(),here/'retained-signals-runtime.c',runtime/'gobject-signals-16.c',runtime/'gobject-signals-16.h',runtime/'foreign-14.c']},checks=[])
	def run(command,contains=''):
		p=subprocess.run(list(map(str,command)),text=True,capture_output=True,cwd=work,timeout=120,env=dict(os.environ,G_DEBUG='fatal-warnings'));receipt['checks'].append(dict(command=list(map(str,command)),exit=p.returncode,stdout=p.stdout,stderr=p.stderr));(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');assert p.returncode==0 and contains in p.stdout+p.stderr,receipt['checks'][-1];return p.stdout
	includes=shlex.split(run(['pkg-config','--cflags','gobject-2.0']));libs=shlex.split(run(['pkg-config','--libs','gobject-2.0']))
	for level in '012':
		client=work/('client-O'+level);run(['cc','-std=gnu11','-Wall','-Wextra','-Werror','-pthread','-O'+level,*includes,'-I'+str(runtime),here/'retained-signals-runtime.c',runtime/'gobject-signals-16.c',runtime/'foreign-14.c',*libs,'-o',client]);run([client],contains='PASS typed retained signal')
		if level in '02':run(['valgrind','--vgdb=no','--default-suppressions=no','--leak-check=full','--show-leak-kinds=definite,indirect,possible','--errors-for-leak-kinds=definite,indirect,possible','--error-exitcode=99',client],contains='ERROR SUMMARY: 0 errors')
	receipt['status']='TYPED_RETAINED_RUNTIME_PASS';(work/'checks.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(dict(status=receipt['status'],commands=len(receipt['checks']),receipt=str(work/'checks.json'))))
if __name__=='__main__':main(*sys.argv[1:])
