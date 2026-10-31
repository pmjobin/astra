# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Physical address limits, runtime imports and an internal freestanding seam."""
from pathlib import Path
import json
import re
import signal
import subprocess
import sys

sys.dont_write_bytecode = True
from execute import ROOT, FIXTURES, run


def qualify(build, out):
	out.mkdir(parents=True, exist_ok=False); rows = []
	compiler = build/'astrac'; emitter = build/'tests/struct-elem-1/astra-struct-elements-llvm'
	assembly = out/'start.S'; assembly.write_text('.text\n.global _start\n_start:\n\txor %ebp, %ebp\n\tand $-16, %rsp\n\tcall main\n\tmov %eax, %edi\n\tmov $60, %eax\n\tsyscall\n.section .note.GNU-stack,"",@progbits\n')
	for name in ['borrowed', 'call-entry']:
		ssa = run([compiler, '--dump-ssa', FIXTURES/(name+'.astra')]); ir = run([compiler, '--dump-llvm', FIXTURES/(name+'.astra')]); ordinal = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		ir += '\ndefine i32 @main(){\n\t%r=call fastcc i32 @astra.fn.'+ordinal+'()\n\tret i32 %r\n}\n'
		for mode in ['O0', 'O2', 'preserved']:
			stem = name+'-'+mode; inp = out/(stem+'-input.ll'); opt = out/(stem+'.ll'); obj = out/(stem+'.o'); binary = out/stem
			inp.write_text(re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M) if mode == 'preserved' else ir)
			run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp.name, '-o', opt.name], out); run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', opt.name, '-o', obj.name], out)
			undefined = run(['nm', '-u', obj]); assert not undefined, (stem, undefined)
			run(['gcc', '-nostdlib', '-static', '-no-pie', assembly, obj, '-o', binary]); assert run([binary]) == ''
			(out/(stem+'.machine')).write_text(run(['objdump', '-dr', obj])); (out/(stem+'.symbols')).write_text(run(['readelf', '-h', '-Ws', '-r', obj])); sizes = run(['size', '-A', obj]); (out/(stem+'.size')).write_text(sizes)
			rows.append(dict(name=stem, undefined=undefined, size=sizes, status=0, freestanding=True))
	for name in ['overflow', 'offset', 'overflow-unsigned', 'offset-unsigned']:
		ir = run([emitter, '--dump-'+name]); inp = out/(name+'-input.ll'); inp.write_text(ir)
		for mode in ['O0', 'O2']:
			stem = name+'-'+mode; opt = out/(stem+'.ll'); obj = out/(stem+'.o'); binary = out/stem
			run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp.name, '-o', opt.name], out); run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', opt.name, '-o', obj.name], out); run(['gcc', obj, '-o', binary]); assert run([binary], status=-signal.SIGILL) == ''
			(out/(stem+'.machine')).write_text(run(['objdump', '-dr', obj])); rows.append(dict(name=stem, status=-signal.SIGILL, category='synthetic physical extent; no giant allocation attempted'))
			# Ordinary values stay scalarized even in a compiler that can address record arrays.
	for name, text in [('scalar', 'int f(int x){return x+1;}'), ('struct', 'struct S{int x;f64 y;}S f(S value){S saved=value;return saved;}'), ('numeric-buffer', 'owned f64[] f(int count){return new f64[count];}'), ('text', 'int f(string value){return value.byte_length;}')]:
		path = out/(name+'.astra'); path.write_text(text+'\n'); ir = run([compiler, '--dump-llvm', path]); (out/(name+'.ll')).write_text(ir)
		if name in ['scalar', 'struct']:
			assert 'alloca' not in ir and 'calloc' not in ir and 'free' not in ir
		rows.append(dict(name=name, allocas=ir.count('alloca '), allocation='@calloc' in ir))
	(out/'results.json').write_text(json.dumps(rows, indent='\t')+'\n')
	print('6 freestanding fixed/borrowed executions; 8 synthetic address-overflow traps; scalarization controls')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
