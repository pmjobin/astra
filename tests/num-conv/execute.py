# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native conversions checked by integer/rational oracles, never host FP casts."""
from fractions import Fraction
from pathlib import Path
import ctypes
import json
import os
import random
import re
import resource
import signal
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'floating'))
from reference import BINARY32 as F32, BINARY64 as F64

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ['int-f32', 'int-f64', 'f32-int', 'f64-int', 'signed', 'unsigned', 'literals', 'order', 'trap', 'cad']
INTEGERS = [('i8', 8, True), ('u8', 8, False), ('i16', 16, True), ('u16', 16, False), ('int', 32, True), ('u32', 32, False)]
FLAGS = r'\b(?:reassoc|nnan|ninf|nsz|arcp|contract|afn|fast)\b|llvm\.(?:fma|fmuladd)'
FUSED = r'\bv?f(?:n?madd|n?msub)\w*\b'


def run(argv, status=0, output=None):
	p = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert p.returncode == status and not p.stderr and (output is None or p.stdout == output), (argv, p)
	return p.stdout


def limits(width, signed):
	return (-(1 << (width-1)), (1 << (width-1))-1) if signed else (0, (1 << width)-1)


def int_values(width, signed):
	low, high = limits(width, signed)
	if width <= 16:
		return range(low, high+1)
	points = {low, low+1, -1, 0, 1, high-1, high}
	for power in range(1, width+1):
		for sign in [-1, 1]:
			points.update(sign*((1 << power)+delta) for delta in range(-5, 6))
	rng = random.Random(width + signed)
	points.update(rng.randrange(low, high+1) for _ in range(4000))
	return sorted(x for x in points if low <= x <= high)


def float_values(fmt, width, signed):
	low, high = limits(width, signed)
	points = {0, fmt.sign, 1, fmt.sign|1, fmt.hidden-1, fmt.sign|(fmt.hidden-1), fmt.hidden, fmt.sign|fmt.hidden}
	for value in [low-1, low, high, high+1, 0, 1, -1, 300]:
		for fraction in [Fraction(-9, 10), Fraction(-1, 2), Fraction(0), Fraction(1, 2), Fraction(9, 10)]:
			bits = fmt.round(Fraction(value) + fraction)
			points.add(bits)
			for delta in [-1, 1]:
				if 0 <= bits+delta < 1 << fmt.width:
					points.add(bits+delta)
	for sign in [0, fmt.sign]:
		points.update(sign|fmt.infinity|payload for payload in [0, 1, 2, fmt.hidden//2, fmt.hidden-1])
		points.add(sign|(fmt.infinity-1))
	rng = random.Random(fmt.width*width + signed)
	points.update(rng.randrange(1 << fmt.width) for _ in range(96))
	return sorted(points)


def truncated(fmt, bits, width, signed):
	if fmt.magnitude(bits) >= fmt.infinity:
		return None
	value = fmt.value(bits)
	result = abs(value.numerator)//value.denominator
	if value < 0:
		result = -result
	low, high = limits(width, signed)
	return result if low <= result <= high else None


def matrix_ir(compiler, out):
	code = []
	pairs = []
	for integer, width, signed in INTEGERS:
		for fmt in [F32, F64]:
			for to_float in [True, False]:
				source, destination = (integer, f'f{fmt.width}') if to_float else (f'f{fmt.width}', integer)
				number = len(pairs)
				code.append(f'{destination} c{number}({source} value) {{ return value as {destination}; }}')
				pairs.append((integer, width, signed, fmt, to_float))
	path = out/'matrix.astra'
	path.write_text('\n'.join(code)+'\n')
	llvm = run([compiler, '--dump-llvm', path])
	llvm = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', llvm, flags=re.M)
	for number, (_, width, signed, fmt, to_float) in enumerate(pairs):
		f = 'float' if fmt.width == 32 else 'double'
		i = f'i{width}'
		lines = [f'define i64 @probe{number}(i64 %raw) {{', 'entry:']
		if to_float:
			lines += [f'\t%input = trunc i64 %raw to {i}', f'\t%result = call fastcc {f} @astra.fn.{number}({i} %input)', f'\t%bits = bitcast {f} %result to i{fmt.width}']
			if fmt.width == 32:
				lines += ['\t%wide = zext i32 %bits to i64', '\tret i64 %wide']
			else:
				lines += ['\tret i64 %bits']
		else:
			bits = '%raw'
			if fmt.width == 32:
				lines += ['\t%bits = trunc i64 %raw to i32']
				bits = '%bits'
			lines += [f'\t%input = bitcast i{fmt.width} {bits} to {f}', f'\t%result = call fastcc {i} @astra.fn.{number}({f} %input)', f'\t%wide = {"sext" if signed else "zext"} {i} %result to i64', '\tret i64 %wide']
		llvm += '\n'.join(lines + ['}'])+'\n'
	return llvm, pairs


def audit_guards(text, pairs):
	assert not re.search(FLAGS, text)
	for number, (_, width, signed, fmt, to_float) in enumerate(pairs):
		body = re.search(r'define [^\n]*@astra\.fn\.'+str(number)+r'\([^\n]*\)[^\n]*\{(.*?)\n}', text, re.S)[1]
		if to_float:
			assert ('sitofp' if signed else 'uitofp') in body and 'llvm.trap' not in body, body
		else:
			# The optimized conversion must remain control dependent on the
			# successful ordered range branch. A constant-folded trap is also safe.
			conversion = re.search(r'\bfpto(?:si|ui)\b', body)
			assert conversion and 'fcmp' in body and 'br i1' in body and 'llvm.trap' in body, body
			prefix = body[:conversion.start()]
			assert re.search(r'\n[^\n]*\.valid:', prefix), body
			assert prefix.index('br i1') < prefix.rindex('.valid:'), body


def compile_ir(out, name, llvm, mode):
	stem = out/(name+'-'+mode)
	input_path = stem.with_suffix('.input.ll')
	input_path.write_text(llvm)
	final_path = stem.with_suffix('.ll')
	if mode == 'O0':
		final_path.write_text(llvm)
	else:
		run(['opt', '-passes=default<O2>', '-S', input_path, '-o', final_path], output='')
	text = final_path.read_text()
	assert not re.search(FLAGS, text)
	run(['opt', '-passes=verify', '-disable-output', final_path], output='')
	run(['llc', '-O0' if mode == 'O0' else '-O2', *(['-mattr=+avx,+fma'] if mode == 'fma' else []), '-filetype=obj', '-relocation-model=pic', final_path, '-o', stem.with_suffix('.o')], output='')
	machine = run(['objdump', '-dr', stem.with_suffix('.o')])
	assert not re.search(FUSED, machine)
	stem.with_suffix('.machine').write_text(machine)
	return stem, text


def campaign(compiler, out, records):
	llvm, pairs = matrix_ir(compiler, out)
	audit_guards(llvm, pairs)
	data = []
	inventory = []
	for number, (integer, width, signed, fmt, to_float) in enumerate(pairs):
		rows = [(value, fmt.round(Fraction(value))) for value in int_values(width, signed)] if to_float else [(bits, truncated(fmt, bits, width, signed)) for bits in float_values(fmt, width, signed)]
		data.append(rows)
		inventory.append(dict(function=number, integer=integer, floating=f'f{fmt.width}', direction='int-to-float' if to_float else 'float-to-int', cases=len(rows), traps=sum(expected is None for _, expected in rows)))
	(out/'matrix-oracle.json').write_text(json.dumps([dict(**row, values=[dict(input=value, expected=expected) for value, expected in values] if row['cases'] < 10000 else 'exhaustive; see deterministic oracle') for row, values in zip(inventory, data)], indent='\t')+'\n')
	for mode in ['O0', 'O2', 'fma']:
		stem, text = compile_ir(out, 'matrix', llvm, mode)
		audit_guards(text, pairs)
		assert run(['nm', '-u', stem.with_suffix('.o')]) == ''
		run(['cc', '-shared', '-nostdlib', stem.with_suffix('.o'), '-o', stem.with_suffix('.so')], output='')
		library = ctypes.CDLL(str(stem.with_suffix('.so')))
		valid = traps = 0
		for number, rows in enumerate(data):
			function = getattr(library, f'probe{number}')
			function.argtypes = [ctypes.c_uint64]
			function.restype = ctypes.c_uint64
			for value, expected in rows:
				if expected is not None:
					actual = function(value & ((1 << 64)-1))
					assert actual == expected & ((1 << 64)-1), (mode, number, value, expected, actual)
					valid += 1
				else:
					pid = os.fork()
					if pid == 0:
						function(value)
						os._exit(97)
					_, status = os.waitpid(pid, 0)
					assert os.WIFSIGNALED(status) and os.WTERMSIG(status) == signal.SIGILL, (mode, number, hex(value), status)
					traps += 1
		print(f'{mode}: {valid} exact results, {traps} guarded traps', flush=True)
		records['matrix_runs'].append(dict(mode=mode, exact_results=valid, traps=traps, undefined_symbols=0, guard_audits=len(pairs)//2))
	records['freestanding'] = []
	for triple in ['x86_64-unknown-none', 'aarch64-none-elf']:
		obj = out/('freestanding-'+triple+'.o')
		run(['llc', '-O2', '-mtriple='+triple, '-filetype=obj', out/'matrix-O2.ll', '-o', obj], output='')
		assert run(['nm', '-u', obj]) == ''
		records['freestanding'].append(dict(triple=triple, undefined_symbols=0))
	records['inventory'] = inventory


def main(compiler, out):
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	out.mkdir(parents=True, exist_ok=True)
	assert 'fma' in Path('/proc/cpuinfo').read_text()
	records = dict(runs=[], matrix_runs=[])
	companion = out/'companion.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT/'tests/num-conv/companion.c', '-o', companion], output='')
	for name in FIXTURES:
		source = ROOT/f'tests/num-conv/fixtures/num-conv-{name}.astra'
		llvm = run([compiler, '--dump-llvm', source])
		ssa = run([compiler, '--dump-ssa', source])
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		llvm += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		status = -signal.SIGILL if name == 'trap' else 0
		output = '12' if name == 'trap' else '1234' if name == 'order' else ''
		run([compiler, source, '--link-object', companion, '-o', out/(name+'-native')], output='')
		run([out/(name+'-native')], status, output)
		records['runs'].append(dict(name=name+'-native', status=status, output=output))
		for mode in ['O0', 'O2', 'fma']:
			stem, _ = compile_ir(out, name, llvm, mode)
			run(['cc', stem.with_suffix('.o'), companion, '-o', stem], output='')
			status = -signal.SIGILL if name == 'trap' else 0
			output = '12' if name == 'trap' else '1234' if name == 'order' else ''
			run([stem], status, output)
			records['runs'].append(dict(name=stem.name, status=status, output=output))
	campaign(compiler, out, records)
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')


if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
