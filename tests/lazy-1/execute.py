# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Native first-success witnesses; observers report effects, never decide caching."""
import hashlib
import json
from pathlib import Path
import re
import signal
import subprocess
import sys

SOURCE = Path(__file__).resolve().parents[2]
FIXTURES = SOURCE / 'tests/lazy-1/fixtures'
CASES = {'basic': (42, 'BAENATOO'), 'retry': (42, 'SFDFVDXOOLX'), 'staging': (42, 'FDVD'), 'lifetime': (42, 'IIIMLQDEDDDID'), 'bits': (42, ''), 'task': (42, ''), 'recursive': (-signal.SIGILL, 'R'), 'helper-recursive': (-signal.SIGILL, 'H'), 'cycle': (-signal.SIGILL, 'AB')}
FLOAT_FLAGS = r'\b(?:reassoc|nnan|ninf|nsz|arcp|contract|afn|fast)\b|llvm\.(?:fma|fmuladd)|unsafe-fp|no-nans|no-infs|no-signed-zeros'

def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()

def value_matrix():
	classes, checks, shapes = [], [], []
	for element, width in [('bool', 1), ('i8', 8), ('u8', 8), ('i16', 16), ('u16', 16), ('int', 32), ('i32', 32), ('u32', 32), ('f32', 32), ('f64', 64)]:
		for lanes in [0, 2, 4, 8, 16]:
			if lanes and (element == 'f64' or width * lanes > 128): continue
			kind = f'{element}<{lanes}>' if lanes else element
			index = len(shapes)
			shapes.append(kind)
			zero = 'false' if element == 'bool' else '0.0' if element.startswith('f') else '0'
			one = 'true' if element == 'bool' else '1.0' if element.startswith('f') else '1'
			getter = f'return splat(this.input, {lanes});' if lanes else 'return this.input;'
			classes.append(f'class C{index}{{{element} input;int calls;init(){{this.input={zero};this.calls=0;}}lazy property {kind} value{{get{{this.calls=this.calls+1;{getter}}}}}}}')
			checks += [f'\tvar object{index}=new C{index}();', f'\t{kind} first{index}=object{index}.value;', f'\tobject{index}.input={one};']
			equal = f'object{index}.value==first{index}'
			checks.append(f'\tif (!({"all("+equal+")" if lanes else equal}) || object{index}.calls!=1) {{ return 81; }}')
	return '\n'.join([*classes, 'int main(){', *checks, '\treturn 42;', '}'])+'\n', shapes

def main(compiler, output):
	output.mkdir(parents=True, exist_ok=True)
	receipts, runs, costs = [], [], []
	identity = {'compiler_sha256': sha(compiler), 'authored_inputs': {str(p.relative_to(SOURCE)): sha(p) for p in FIXTURES.iterdir() if p.is_file()}, 'receipts': receipts, 'runs': runs, 'costs': costs}
	def run(name, argv, expected=0, stdout=None):
		p = subprocess.run(list(map(str, argv)), cwd=SOURCE, capture_output=True, timeout=90)
		row = {'name': name, 'command': list(map(str, argv)), 'expected_exit': expected, 'actual_exit': p.returncode, 'stdout_sha256': hashlib.sha256(p.stdout).hexdigest(), 'stderr_sha256': hashlib.sha256(p.stderr).hexdigest(), 'status': 'PASS' if p.returncode == expected and not p.stderr and (stdout is None or p.stdout.decode() == stdout) else 'FAIL'}
		receipts.append(row)
		(output / 'receipts.json').write_text(json.dumps(identity, separators=(',', ':'))+'\n')
		assert row['status'] == 'PASS', (name, argv, p.returncode, p.stdout[-2000:], p.stderr[-5000:])
		return p.stdout.decode()
	helper = output / 'observer.o'
	run('strict-observer', ['gcc', '-Wall', '-Wextra', '-Werror', '-std=c11', '-c', FIXTURES/'observer.c', '-o', helper])
	matrix, identity['value_shapes'] = value_matrix()
	(output/'matrix.astra').write_text(matrix)
	cases = dict(CASES, matrix=(42, ''), cleanup=(-signal.SIGILL, 'CD'), reuse=(42, 'RR'))
	for name, (expected, trace) in cases.items():
		inputs = [output/'matrix.astra' if name == 'matrix' else FIXTURES/(name+'.astra')]
		options = []
		objects = [helper]
		link_options = []
		if name in ('retry', 'staging', 'cleanup'): options += ['--vapi', FIXTURES/'observer.vapi']
		if name in ('cleanup', 'reuse'):
			special = output/(name+'-observer.o')
			run(name+'-strict-observer', ['gcc', '-Wall', '-Wextra', '-Werror', '-std=c11', '-c', FIXTURES/(name+'.c'), '-o', special])
			objects = [special] if name == 'cleanup' else [helper, special]
			link_options = ['-Wl,--wrap=calloc'] + (['-Wl,--wrap=free'] if name == 'reuse' else [])
		if name in ('lifetime', 'staging', 'task'): inputs += [SOURCE/'lib/astra/base/errors.astra']
		if name == 'task': inputs += [SOURCE/'lib/astra/async/virtual.astra']; objects += [compiler.parent/'lib/astra/async-virtual.o']
		links = [arg for obj in objects for arg in ['--link-object', obj]]
		if name in ('cleanup', 'reuse'):
			run(name+'-CLI-check', [compiler, '--check', *inputs, *options])
		else:
			run(name+'-CLI-build', [compiler, *inputs, *options, *links, '-o', output/name])
			run(name+'-CLI-run', [output/name], expected, trace)
			runs.append({'name': name+'-CLI', 'expected_exit': expected, 'trace': trace, 'fatal': expected < 0})
		ssa = run(name+'-SSA', [compiler, '--dump-ssa', *inputs, *options])
		ir = run(name+'-LLVM', [compiler, '--dump-llvm', *inputs, *options])
		assert '(lazy first-success empty/evaluating/ready)' in ssa and 'lazy.is.ready' in ir and 'astra.lazy.body.' in ir
		assert not re.search(FLOAT_FLAGS, ir)
		if name == 'basic':
			plans = run(name+'-NABI-cost', [compiler, '--dump-nabi', *inputs, *options])
			layout_probe = ir
			owners = {}
			for owner, member in re.findall(r'lazy-cache v1 class=#(\d+).*?state-member=(\d+)', plans):
				owners.setdefault(int(owner), int(member))
			for owner, member in owners.items():
				fields = re.search(r'^%astra.class.'+str(owner)+r' = type \{ (.*) \}$', ir, re.M)[1].split(', ')
				layout_probe += '\n%lazy.cost.base.'+str(owner)+' = type { '+', '.join(fields[:member])+' }\n'
				for variant, kind in [('complete', 'astra.class'), ('ordinary', 'lazy.cost.base')]:
					layout_probe += f'\ndefine i64 @lazy.cost.{variant}.{owner}() {{\n\t%end = getelementptr %{kind}.{owner}, ptr null, i32 1\n\t%bytes = ptrtoint ptr %end to i64\n\tret i64 %bytes\n}}\n'
			probe = output/'layout-cost-input.ll'
			probe.write_text(layout_probe)
			run('target-layout-cost', ['opt', '-passes=instcombine', '-S', probe, '-o', output/'layout-cost.ll'])
			measured = (output/'layout-cost.ll').read_text()
			identity['target_layout_costs'] = []
			for owner in owners:
				pair = {variant: int(re.search(r'define i64 @lazy.cost.'+variant+'.'+str(owner)+r'\(\).*?ret i64 (\d+)', measured, re.S)[1]) for variant in ('complete', 'ordinary')}
				identity['target_layout_costs'].append({'class_ordinal': owner, 'ordinary_bytes': pair['ordinary'], 'complete_bytes': pair['complete'], 'cache_payload_state_padding_bytes': pair['complete']-pair['ordinary'], 'state_bytes': len(re.findall(r'lazy-cache v1 class=#'+str(owner)+r' ', plans))})
		identifier = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		ir += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+identifier+'()\n\tret i32 %result\n}\n'
		if name == 'cleanup':
			# A valid C-convention bridge calls the admitted gate on the actual allocation.
			# The observer invokes it during Resource cleanup without altering the gate/body.
			ir += '\ndefine i32 @lazy_cleanup_bridge(ptr %receiver) {\n\t%value = call fastcc i32 @astra.propget.class.0.0(ptr %receiver)\n\tret i32 %value\n}\n'
		for mode in ('O0', 'O2', 'callable-O2-fma'):
			stem = name+'-'+mode
			text = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', ir, flags=re.M) if mode.startswith('callable') else ir
			input_ir, optimized, obj = output/(stem+'-input.ll'), output/(stem+'.ll'), output/(stem+'.o')
			input_ir.write_text(text)
			run(stem+'-opt', ['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', input_ir, '-o', optimized])
			run(stem+'-verify', ['opt', '-passes=verify', '-disable-output', optimized])
			assert not re.search(FLOAT_FLAGS, optimized.read_text())
			run(stem+'-object', ['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', *(['-mattr=+fma'] if mode.endswith('fma') else []), optimized, '-o', obj])
			run(stem+'-link', ['gcc', obj, *objects, *link_options, '-o', output/stem])
			run(stem+'-run', [output/stem], expected, trace)
			runs.append({'name': stem, 'expected_exit': expected, 'trace': trace, 'fatal': expected < 0})
			machine = run(stem+'-size', ['size', obj])
			assembly = run(stem+'-machine', ['objdump', '-dr', obj])
			assert not re.search(r'\bv?f(?:n?madd|n?msub)\w*\b', assembly)
			if name == 'basic' and mode == 'callable-O2-fma':
				gate = re.search(r'define fastcc i32 @astra.propget.class.0.0\([^\n]+\).*?\{\n(.*?)^}', optimized.read_text(), re.M|re.S)[1]
				assert 'astra.lazy.body.0.0' in gate and 'lazy.state' in gate and 'lazy.ready' in gate and 'lazy.recursive.trap' in gate
			costs.append({'name': stem, 'object_bytes': obj.stat().st_size, 'size': machine.strip(), 'LLVM_cache_gates': len(re.findall(r'^define .*@astra.propget', text, re.M)), 'LLVM_gate_conditional_branches': len(re.findall(r'br i1 %lazy\.', text)), 'LLVM_initializer_calls': len(re.findall(r'call fastcc .*@astra.lazy.body', text))})
	identity['status'] = 'PASS'
	(output/'receipts.json').write_text(json.dumps(identity, separators=(',', ':'))+'\n')
	print(f'LAZY finite native PASS: {len(runs)} executions; {len(identity["value_shapes"])} copied shapes; {len(receipts)} exact-exit receipts')

if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
