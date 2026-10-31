# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native scalar f64 qualification, exact physical bit checks and FMA audit.

The generated LLVM test entry calls Astra's internal fastcc boundaries directly;
there are no Astra C floating declarations and no host floating oracle.
"""
from pathlib import Path
import json
import os
import random
import re
import signal
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'floating'))
from reference import BINARY32 as F32, BINARY64 as F64

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['basic', 'literal', 'round', 'special', 'compare', 'convert', 'call', 'loop', 'pointer', 'pointer-null', 'array', 'slice', 'object', 'ownership', 'channels']
FLAGS = r'\b(?:reassoc|nnan|ninf|nsz|arcp|contract|afn|fast)\b|llvm\.(?:fma|fmuladd)|unsafe-fp|no-nans|no-infs|no-signed-zeros'
FUSED = r'\bv?f(?:n?madd|n?msub)\w*\b'


def run(argv, status=0, output=None):
	p = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert p.returncode == status and not p.stderr and (output is None or p.stdout == output), (argv, p)
	return p.stdout


def audited_ir(text):
	assert not re.search(FLAGS, text)
	assert not re.search(r'"denormal-fp-math[^"\n]*"="(?!ieee,ieee)', text)


def physical_matrix(compiler, out):
	ops = ['+', '-', '*', '/']
	predicates = ['==', '!=', '<', '<=', '>', '>=']
	code = '\n'.join(f'f64 arithmetic{i}(f64 a,f64 b){{return a {op} b;}}' for i, op in enumerate(ops))
	code += '\n' + '\n'.join(f'bool compare{i}(f64 a,f64 b){{return a {op} b;}}' for i, op in enumerate(predicates))
	code += '\nf64 negate(f64 x){return -x;}\nf64 widen(f32 x){return x as f64;}\nf32 narrow(f64 x){return x as f32;}\n'
	(out/'matrix.astra').write_text(code)
	llvm = run([compiler, '--dump-llvm', out/'matrix.astra'])
	llvm = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', llvm, flags=re.M)
	lines = [llvm]
	groups = []
	group_checks = []
	checks = []
	def arg(fmt, bits):
		return f'{"float" if fmt.width == 32 else "double"} bitcast (i{fmt.width} {bits} to {"float" if fmt.width == 32 else "double"})'
	def check(function, arguments, expected, fmt=None):
		i = len(checks)
		if i % 64 == 0:
			groups.append(i // 64)
			lines.extend([f'define internal i1 @checkgroup{i // 64}() noinline {{', 'entry:'])
		type_name = 'i1' if fmt is None else 'float' if fmt.width == 32 else 'double'
		lines.append(f'\t%r{i} = call fastcc {type_name} @astra.fn.{function}({", ".join(arguments)})')
		if fmt is None:
			lines.append(f'\t%ok{i} = icmp eq i1 %r{i}, {str(expected).lower()}')
		else:
			lines.append(f'\t%bits{i} = bitcast {type_name} %r{i} to i{fmt.width}')
			if fmt.is_nan(expected):
				lines.append(f'\t%mag{i} = and i{fmt.width} %bits{i}, {fmt.sign - 1}')
				lines.append(f'\t%ok{i} = icmp ugt i{fmt.width} %mag{i}, {fmt.infinity}')
			else:
				lines.append(f'\t%ok{i} = icmp eq i{fmt.width} %bits{i}, {expected}')
		checks.append(i)
		group_checks.append(i)
		if len(group_checks) == 64:
			finish_group()
	def finish_group():
		last = 'true'
		for i in group_checks:
			lines.append(f'\t%pass{i} = and i1 {last}, %ok{i}')
			last = f'%pass{i}'
		lines.extend([f'\tret i1 {last}', '}'])
		group_checks.clear()
	selected = [0, 1, 2, F64.hidden - 1, F64.hidden, (F64.bias - 1) << 52, F64.bias << 52, (F64.bias << 52) + 1, 0x4340000000000000, F64.infinity - 1, F64.infinity, F64.nan, F64.infinity | 1]
	selected += [bits | F64.sign for bits in selected]
	pairs = [(a, b) for a in selected for b in selected]
	rng = random.Random(0xF64A)
	pairs += [(rng.randrange(1 << 64), rng.randrange(1 << 64)) for _ in range(128)]
	for a, b in pairs:
		for i, op in enumerate(ops):
			check(i, [arg(F64, a), arg(F64, b)], F64.arithmetic(op, a, b), F64)
		for i, op in enumerate(predicates, 4):
			check(i, [arg(F64, a), arg(F64, b)], F64.compare(op, a, b))
	for bits in selected:
		check(10, [arg(F64, bits)], bits ^ F64.sign, F64)
	wide = {sign | (field << 23) | frac for field in range(256) for frac in [0, 1, F32.hidden - 1] for sign in [0, F32.sign]}
	wide.update(rng.randrange(1 << 32) for _ in range(512))
	narrow = {F32.convert(bits, F64) for bits in wide}
	for bits in sorted(wide):
		check(11, [arg(F32, bits)], F32.convert(bits, F64), F64)
	for low in [0, 1, F32.hidden - 1, F32.hidden, 0x3f7fffff, 0x3f800000, 0x3f800001, F32.infinity - 1]:
		upper = F32.value(low + 1) if low < F32.infinity - 1 else 1 << 128
		tie = F64.round((F32.value(low) + upper) / 2)
		narrow.update((tie + d) | sign for d in [-1, 0, 1] for sign in [0, F64.sign])
	narrow.update(selected)
	narrow.update(rng.randrange(1 << 64) for _ in range(512))
	for bits in sorted(narrow):
		check(12, [arg(F64, bits)], F64.convert(bits, F32), F32)
	if group_checks:
		finish_group()
	lines.extend(['define i32 @main() {', 'entry:'])
	last = 'true'
	for i in groups:
		lines.append(f'\t%ok{i} = call i1 @checkgroup{i}()')
		lines.append(f'\t%pass{i} = and i1 {last}, %ok{i}')
		last = f'%pass{i}'
	lines.extend([f'\t%status = select i1 {last}, i32 0, i32 1', '\tret i32 %status', '}'])
	return '\n'.join(lines) + '\n', dict(pairs=len(pairs), arithmetic_comparison_checks=len(pairs) * 10, unary_checks=len(selected), widening_checks=len(wide), narrowing_checks=len(narrow), exact_bit_or_nan_checks=len(checks))


def compile_ir(stem, llvm, companion, mode, records, status=0, output=''):
	text = llvm
	if mode == 'fma':
		text = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', text, flags=re.M)
	input_path = stem.with_suffix('.input.ll')
	input_path.write_text(text)
	final_path = stem.with_suffix('.ll')
	if mode in ['O2', 'fma']:
		run(['opt', '-passes=default<O2>', '-S', input_path, '-o', final_path], output='')
	else:
		final_path.write_text(text)
	audited_ir(final_path.read_text())
	run(['opt', '-passes=verify', '-disable-output', final_path], output='')
	options = ['-mattr=+avx,+fma'] if mode == 'fma' else []
	run(['llc', '-O0' if mode == 'O0' else '-O2', *options, '-filetype=obj', '-relocation-model=pic', final_path, '-o', stem.with_suffix('.o')], output='')
	machine = run(['objdump', '-dr', stem.with_suffix('.o')])
	assert not re.search(FUSED, machine), stem
	stem.with_suffix('.machine').write_text(machine)
	run(['cc', stem.with_suffix('.o'), companion, '-o', stem], output='')
	run([stem], status, output)
	records['runs'].append(dict(name=stem.name, status=status, output=output))
	return machine


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	assert 'fma' in Path('/proc/cpuinfo').read_text(), 'FMA-capable audit host required'
	companion = out/'companion.o'
	run(['cc', '-std=c11', '-Werror', '-Wall', '-Wextra', '-c', ROOT/'tests/obj-life/companion.c', '-o', companion], output='')
	records = dict(runs=[], machine=[], profiles={})
	for name in FIXTURES:
		source = ROOT/f'tests/f64/fixtures/f64-{name}.astra'
		options = ['--vapi', ROOT/'tests/obj-life/fixtures/lifecycle.vapi'] if name == 'ownership' else []
		status = -signal.SIGILL if name == 'pointer-null' else 0
		output = 'ACPQBD' if name == 'ownership' else ''
		run([compiler, source, *options, '--link-object', companion, '-o', out/name], output='')
		run([out/name], status, output)
		records['runs'].append(dict(name=name, status=status, output=output))
		llvm = run([compiler, '--dump-llvm', source, *options])
		audited_ir(llvm)
		ssa = run([compiler, '--dump-ssa', source, *options])
		nabi = run([compiler, '--dump-nabi', source, *options])
		for suffix, text in [('ssa', ssa), ('nabi', nabi)]:
			(out/(name+'.'+suffix)).write_text(text)
		records['profiles'][name] = re.search(r'\(native-abi ([\w-]+)', nabi)[1]
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		llvm += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		for mode in ['O0', 'O2', *(['fma'] if name in ['basic', 'round', 'convert', 'special'] else [])]:
			machine = compile_ir(out/(name+'-'+mode), llvm, companion, mode, records, status, output)
			if name == 'round' and mode == 'fma':
				assert 'vmulsd' in machine and 'vaddsd' in machine
			if name == 'basic' and mode == 'O0':
				assert all(op in machine for op in ['addsd', 'subsd', 'mulsd', 'divsd'])
			if name == 'convert' and mode == 'O0':
				assert 'cvtss2sd' in machine and 'cvtsd2ss' in machine
		linkage = run(['ldd', out/name])
		assert not re.search(r'libglib|libgobject|libLLVM', linkage), name
		records['machine'].append(name)
	assert records['profiles']['slice'] == 'slice-v5'
	assert records['profiles']['pointer'] == 'scalar-ptr-v1'
	assert records['profiles']['array'] == 'scalar-v0'
	assert records['profiles']['channels'] == records['profiles']['ownership'] == 'fp64-v6'
	llvm, matrix = physical_matrix(compiler, out)
	for mode in ['O0', 'O2', 'fma']:
		compile_ir(out/('matrix-'+mode), llvm, companion, mode, records)
		# The qualified process environment: nearest/even, masks, no FTZ/DAZ.
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', ROOT/'tests/f64/environment.c', '-lm', '-o', out/'environment'], output='')
	run([out/'environment'], output='')
	bad = out/'bad-entry.astra'
	bad.write_text('f64 main(){return 0.0;}\n')
	p = subprocess.run([str(compiler), str(bad), '-o', str(out/'bad-entry')], text=True, capture_output=True)
	assert p.returncode == 1 and 'main must return int' in p.stderr and not (out/'bad-entry').exists()
	records.update(matrix=matrix, environment='FE_TONEAREST, all SSE exceptions masked, FTZ/DAZ off', fma_capable_host=True, f64_main_rejected=True)
	(out/'results.json').write_text(json.dumps(records, indent='\t') + '\n')
	print(json.dumps(dict(runtime_executions=len(records['runs']), machine_fixtures=len(records['machine']), **matrix)), flush=True)


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
