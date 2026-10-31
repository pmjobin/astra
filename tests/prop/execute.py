# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Computed property runtime, direct-call, effect, alias, F64 and machine audits."""
from pathlib import Path
import json
import os
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/prop/fixtures'
CASES = {name: (42, '') for name in ['basic', 'readonly', 'alias', 'struct', 'method', 'constructor', 'bool', 'f32', 'f64', 'vector', 'pointer', 'recursive']}
CASES.update({'effect': (42, 'RSGG'), 'life': (42, 'SsGgD'), 'owned': (42, '*'), 'result': (42, '*'), 'null-get': (-signal.SIGILL, ''), 'null-set': (-signal.SIGILL, '')})
FLAGS = r'\b(?:reassoc|nnan|ninf|nsz|arcp|contract|afn|fast)\b|llvm\.(?:fma|fmuladd)|unsafe-fp|no-nans|no-infs|no-signed-zeros'


def run(argv, status=0, output=None):
	p = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert p.returncode == status and not p.stderr and (output is None or p.stdout == output), (argv, p)
	return p.stdout


def value_matrix():
	declarations = []
	checks = []
	shapes = []
	for element, bits in [('bool', 1), ('i8', 8), ('u8', 8), ('i16', 16), ('u16', 16), ('int', 32), ('u32', 32), ('f32', 32), ('f64', 64)]:
		for lanes in [0, 2, 4, 8, 16]:
			if lanes and (element == 'f64' or bits * lanes > 128):
				continue
			type_name = f'{element}<{lanes}>' if lanes else element
			index = len(shapes)
			shapes.append(type_name)
			values = ['false', 'true'] if element == 'bool' else ['-0.0', '1.0000000000000002'] if element == 'f64' else ['-0.0', '1.401298464324817e-45'] if element == 'f32' else ['0', str(2**bits-1)] if element.startswith('u') else [str(-2**(bits-1)), str(2**(bits-1)-1)]
			count = lanes or 1
			fields = ''.join(f'{element} v{i};' for i in range(count))
			getter = f'{type_name} result={{'+','.join(f'this.v{i}' for i in range(count))+'};return result;' if lanes else 'return this.v0;'
			setter = ''.join(f'this.v{i}=next[{i}];' if lanes else 'this.v0=next;' for i in range(count))
			declarations.append(f'struct S{index}{{{fields}property {type_name} value{{get{{{getter}}}set({type_name} next){{{setter}}}}}}}')
			initial = ','.join(f'v{i}={values[0]}' for i in range(count))
			checks.append(f'\tS{index} s{index}={{{initial}}};')
			for n in range(2):
				initial = '{'+','.join(values[(i+n)%2] for i in range(count))+'}' if lanes else values[n]
				checks.append(f'\t{type_name} expected{index}_{n}={initial};')
				checks.append(f'\ts{index}.value=expected{index}_{n};')
				equality = f's{index}.value==expected{index}_{n}'
				checks.append('\tif (!('+(f'all({equality})' if lanes else equality)+')) { return 1; }')
	return '\n'.join([*declarations, 'int main(){', *checks, '\treturn 42;', '}'])+'\n', shapes


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	companion = out / 'companion.o'
	run(['cc', '-c', ROOT/'tests/obj-life/companion.c', '-o', companion])
	records = {'runs': [], 'machine': [], 'transport_bits': []}
	matrix, records['value_shapes'] = value_matrix()
	(out/'matrix.astra').write_text(matrix)

	def compile_ir(stem, ir, status, output, optimize=False, fma=False):
		input_path = out / (stem+'-input.ll')
		input_path.write_text(ir)
		path = out / (stem+'.ll')
		run(['opt', '-passes=default<O2>' if optimize else '-passes=verify', '-S', input_path, '-o', path])
		run(['opt', '-passes=verify', '-disable-output', path])
		assert not re.search(FLAGS, path.read_text()), stem
		obj = out / (stem+'.o')
		run(['llc', '-O2' if optimize else '-O0', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if fma else []), path, '-o', obj])
		run(['cc', obj, companion, '-o', out/stem])
		run([out/stem], status, output)
		disassembly = run(['objdump', '-dr', obj])
		(out/(stem+'.disassembly')).write_text(disassembly)
		assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b', disassembly), stem
		(out/(stem+'.symbols')).write_text(run(['readelf', '-h', '-Ws', obj]))
		records['runs'].append(dict(name=stem, status=status, output=output))

	for name, (status, output) in dict(CASES, matrix=(42, '')).items():
		options = ['--vapi', ROOT/'tests/obj-life/fixtures/lifecycle.vapi'] if name == 'life' else []
		source = out/'matrix.astra' if name == 'matrix' else FIXTURES / ('prop-'+name+'.astra')
		run([compiler, source, *options, '--link-object', companion, '-o', out/name], output='')
		run([out/name], status, output)
		records['runs'].append(dict(name=name, status=status, output=output))
		stages = {stage: run([compiler, '--dump-'+stage, source, *options]) for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']}
		for stage, text in stages.items():
			(out/(name+'.'+stage)).write_text(text)
			assert not re.search(r'PropertyPlace|PropertyStorage|AccessorPlace|LanePlace|backing.field|property.table|vtable', text), name
		ir = stages['llvm']
		assert not re.search(r'(?<![\w.])(?:noalias|readonly|readnone|nonnull|pure)(?![\w.])', ir), name
		assert not re.search(FLAGS, ir), name
		accessors = re.findall(r'^define internal fastcc ([^\n]+) @(astra\.prop(?:get|set)\.(?:class|struct)\.\d+\.\d+)\(([^\n]+)\) \{\n(.*?)^}', ir, re.M | re.S)
		assert accessors, name
		for result, symbol, parameters, body in accessors:
			assert parameters.startswith('ptr %this') and not re.search(r'icmp (?:eq|ne) ptr %this, null', body), (name, symbol)
			assert not re.search(r'call (?:fastcc )?[^\n]* %\w+\(', body), (name, symbol)
		main_id = re.search(r'\(function #(\d+) "main" -> int', stages['ssa'])[1]
		ir += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		compile_ir(name+'-O0', ir, status, output)
		compile_ir(name+'-O2', ir, status, output, True)
		preserved = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M)
		compile_ir(name+'-callable-O2', preserved, status, output, True, name == 'f64')
		if name == 'f64':
			assert 'double @astra.propget.class.0.0(ptr %this)' in stages['llvm']
			assert '@astra.propset.class.0.0(ptr %this, double %p0)' in stages['llvm']
			assert 'fp64-v6' in stages['nabi']
			assert 'mulsd' in (out/(name+'-callable-O2.disassembly')).read_text()
			assert 'addsd' in (out/(name+'-callable-O2.disassembly')).read_text()
		if name == 'struct':
			storage = re.findall(r'\(storage #\d+ \"[^\n]+', stages['ssa'])
			assert len(storage) == 1 and '"b"' in storage[0], storage
		if name == 'null-set':
			body = stages['llvm'].split('define internal fastcc void @astra.propset')[0]
			assert body.index('br i1 true, label %object.guard') < body.index('call i32 @life_record') < body.index('call fastcc void @astra.propset')
		if name == 'basic':
			assert stages['ssa'].count('= property-get ') == 1 and stages['ssa'].count('(property-set ') == 1
		linkage = run(['ldd', out/name])
		assert not re.search(r'libglib|libgobject|libLLVM', linkage), name
		(out/(name+'.linkage')).write_text(linkage)
		records['machine'].append(dict(name=name, accessors=len(accessors), target='default x86-64', receiver='PTR', linkage='internal fastcc'))

		# Exact accessor transport witness, including NaN payloads, with no host float oracle.
	source = out/'transport.astra'
	source.write_text('class Signal{f64 raw;property f64 gain{get{return this.raw;}set(f64 next){this.raw=next;}}}\n')
	ir = run([compiler, '--dump-llvm', source])
	ir = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M)
	bits = [0, 1<<63, 1, (1<<63)|1, 0x0010000000000000, 0x3ff0000000000001, 0x7fefffffffffffff, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8123456789abc, 0xfff8abcdef123456]
	lines = [ir, 'define i32 @main() {', '\t%storage = alloca %astra.class.0, align 8']
	for i, value in enumerate(bits):
		lines += [f'\tcall fastcc void @astra.propset.class.0.0(ptr %storage, double bitcast (i64 {value} to double))', f'\t%r{i} = call fastcc double @astra.propget.class.0.0(ptr %storage)', f'\t%b{i} = bitcast double %r{i} to i64', f'\t%c{i} = icmp eq i64 %b{i}, {value}', f'\tbr i1 %c{i}, label %next{i}, label %bad', f'next{i}:']
	lines += ['\tret i32 42', 'bad:', '\tret i32 1', '}']
	transport = '\n'.join(lines)+'\n'
	compile_ir('transport-O0', transport, 42, '')
	compile_ir('transport-O2-fma', transport, 42, '', True, True)
	records['transport_bits'] = [f'{value:016x}' for value in bits]
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['machine'])} machine audits; {len(bits)} exact F64 transport patterns")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
