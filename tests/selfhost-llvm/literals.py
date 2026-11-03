#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Additional width-sensitive regression; never counted among the frozen 24."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
from oracle import inspect, memory

# Predeclared before emission: complement flips exactly W bits, so ~5=-6 for
# signed widths and ~0 is all ones for unsigned widths. No C0-derived answer.
SOURCE = 'int main(){int x=~5;u32 y=~0;i8 a=~5;i64 b=~0;u32 z=~4294967295;if(x!=-6||y!=4294967295||a!=-6||b!=-1||z!=0){return 1;}return 0;}'


def main():
	p = argparse.ArgumentParser()
	for key in ('component','compiler','build','runtime'):
		p.add_argument('--'+key,type=Path,required=True)
	p.add_argument('--mode',choices=('O0','O2'),required=True)
	a = p.parse_args(); a.runtime.mkdir(parents=True,exist_ok=False); a.build.mkdir(parents=True,exist_ok=True)
	source = a.runtime/'complemented-literals.astra'; source.write_text(SOURCE)
	obj = a.build/('complemented-literals-'+a.mode+'.o'); ir = obj.with_suffix('.ll'); exe = obj.with_suffix('.native'); reference = obj.with_suffix('.c0')
	commands = []
	def run(argv,name):
		r = subprocess.run(list(map(str,argv)),capture_output=True,timeout=60,cwd=a.build)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str,argv)),exit=r.returncode))
		(a.runtime/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
		assert r.returncode == 0,(name,r.returncode,r.stderr[-1600:])
		return r
	ssa = run([a.component,'--ssa',source],'ssa').stdout
	run([a.component,'--llvm-raw',a.mode,ir,source],'raw'); inspect(ir.read_bytes(),ssa)
	run(['llvm-as',ir,'-o',obj.with_suffix('.bc')],'parse')
	run([a.component,'--emit-obj',a.mode,obj,source],'object'); run(['gcc',obj,'-o',exe],'link')
	run([a.compiler,'-'+a.mode,source,'-o',reference],'C0-compile')
	memories = {}
	for name,path in [('native',exe),('C0',reference)]:
		actual = run([path],name); assert not actual.stdout and not actual.stderr
		r = run(['valgrind','--default-suppressions=no','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',path],name+'-memory'); memories[name] = memory(r.stderr)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS',mode=a.mode,counted_in_frozen_24=False,source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),expected_exit=0,memory=memories,artifacts={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in (obj,ir,exe,reference)}),indent=2)+'\n')
	print(a.mode,'complemented literal regression PASS',flush=True)


if __name__ == '__main__':
	main()
