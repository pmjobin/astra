# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Original owner pointers, both Class domains, O2, standard memory and faults."""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent
CASES = {
	'mixed': ('I10 A I20 L10 B10 D10 L20 B20 K20 B20 D20 F20 Z2:1', 8),
	'reverse': ('A I20 I10 L20 B20 K20 B20 D20 F20 L10 B10 D10 Z2:1', 8),
	'early': ('A I30 I31 L30 B30 D30 F30 L31 B31 D31 Z2:1', 6),
	'nested': ('A I40 A I41 B40 K40 B40 D40 F40 D41 F41 Z2:2', 7),
	'before': ('A I42 I43 B42 D42 F42 D43 Z2:1', 5),
	'nodeinit': ('A I50 A I51 L50 B50 F50 L51 B51 K51 B51 F51 Z2:2', 8),
	'derived': ('A I60 I61 L60 B60 d60 D60 F60 L61 B61 K61 B61 d61 D61 Z2:1', 10),
	'child': ('A I62 A I63 L63 B63 K63 B63 D62 F62 F63 Z2:2', 6),
	'null': ('Z0:0', 0),
	'scalars': ('A I64 B64 K64 B64 D64 F64 Z1:1', 0),
}
STAGES = ['semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'llvm']


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows, plans, saved = [], [], {}

	def run(command, status=0, stdout=None, memory=False, diagnostic=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60, env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == status and (stdout is None or stdout == p.stdout)
		if memory:
			valid &= 'ERROR SUMMARY: 0 errors' in p.stderr and 'in use at exit: 0 bytes in 0 blocks' in p.stderr and '(suppressed: 0 from 0)' in p.stderr
		elif diagnostic:
			valid &= diagnostic in p.stderr
		else:
			valid &= not p.stderr
		rows.append(dict(command=command, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, passed=valid, memory=memory, intentional_fault=bool(diagnostic) or status == 98))
		(output / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
		assert valid, rows[-1]
		return p.stdout

	objects = {}
	for name, flags in [('observer', []), ('memory', ['-DOWN_MEMORY']), ('client', ['-DOWN_CLIENT']), ('client-memory', ['-DOWN_CLIENT', '-DOWN_MEMORY'])]:
		objects[name] = output / (name + '.o')
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', *flags, '-c', FIXTURES / 'observer.c', '-o', objects[name]])
	vg = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all']

	def assemble(ir, name, companion, optimize=True):
		path, optimized, obj, binary = [output / (name + suffix) for suffix in ['.ll', '-opt.ll', '.o', '']]
		path.write_text(ir)
		run(['opt', '-passes=default<O2>' if optimize else '-passes=verify', '-S', path, '-o', optimized])
		run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O2' if optimize else '-O0', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj])
		run(['cc', obj, companion, '-o', binary])
		return binary

	entry = '\ndefine i32 @%s(){\n %%r=call fastcc i32 @astra.fn.%s()\n ret i32 %%r\n}\n'
	for name, (tokens, pointers) in CASES.items():
		trace = '\n'.join(tokens.split()) + '\n'
		memory_trace = '\n'.join(re.sub(r'Z(\d+):\d+', r'Z\1:0', x) for x in tokens.split() if x != 'A' and not x.startswith('F')) + '\n'
		inputs = [FIXTURES / (name + '.astra'), FIXTURES / 'support.astra', ROOT / 'tests/gen-own-2a/support.astra']
		if name == 'reverse':
			inputs.reverse()
		for mode, expected in [('observer', trace), ('memory', memory_trace)]:
			binary = output / (name + '-' + mode)
			run([compiler, *inputs, '--link-object', objects[mode], '-o', binary])
			run([*vg, binary] if mode == 'memory' else [binary], 42, expected, memory=mode == 'memory')
		dumps = {stage: run([compiler, '--dump-' + stage, *inputs]) for stage in STAGES}
		for stage, text in dumps.items():
			(output / (name + '.' + stage)).write_text(text)
			if stage in ['instances', 'cfg', 'ssa', 'nabi', 'llvm']:
				assert not re.search(r'type-parameter|OWNABLE|ownership-contract|generic-op', text)
		assert dumps['instances'] == run([compiler, '--dump-instances', *inputs])
		ir, ssa = dumps['llvm'], dumps['ssa']
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		saved[name] = ir + entry % ('main', main_id)
		for mode, expected in [('observer', trace), ('memory', memory_trace)]:
			binary = assemble(saved[name], name + '-' + mode + '-O2', objects[mode])
			run([*vg, binary] if mode == 'memory' else [binary], 42, expected, memory=mode == 'memory')
		if name in ['null', 'scalars']:
			continue
		client_ir, count = re.subn(r'(define internal fastcc void @astra.ctor.\d+\(ptr %this, i32 %p0, i32 %p1[^\n]*\) \{\n\w+:[^\n]*\n)', lambda m: m[1] + '  call void @own_pointer(ptr %this, i32 %p0, i32 %p1, i32 1)\n', ir)
		assert count == 6, count
		instances = re.findall(r'\(generic-instance #(\d+) \(origin #(\d+) "([^"]+)"\) \(type-arguments ([^)]*)\)(?: \(heap-owned-parameter #(\d+)\))?', dumps['instances'])
		assert len({(x[1], x[3], x[4]) for x in instances}) == len(instances)
		if name in ['mixed', 'reverse']:
			pair = [x for x in instances if x[2] == 'stage']
			assert len(pair) == 2 and {x[3] for x in pair} == {'Counter'} and {x[4] for x in pair} == {'', '1'}
			assert bool(pair[0][4]) == (name == 'reverse')
		for instance, origin, helper, actual, heap_slot in instances:
			ordinal = re.search(r'\(function #(\d+) "astra.gen.' + origin + '.' + instance + '"', ssa)[1]
			pattern = r'(define internal fastcc (?:void|i32) @astra.fn.' + ordinal + r'\(([^\n]*)\) \{\n\w+:[^\n]*\n)(.*?)^}'
			body = re.search(pattern, ir, re.M | re.S)
			assert body and not re.search(r'alloca |llvm\.mem(?:cpy|move)|result.storage|@calloc', body[0]), (name, helper)
			owner, identifier = (1, 0) if helper == 'stage' else (0, 1)
			assert not heap_slot or int(heap_slot) == owner
			if helper == 'loan':
				check = f'  call void @own_loan(ptr %p{owner}, i32 %p{identifier})\n'
				assert '@free(' not in body[3] and '@astra.dtor' not in body[3]
			else:
				check = f'  call void @own_pointer(ptr %p{owner}, i32 %p{identifier}, i32 {int(bool(heap_slot))}, i32 0)\n'
				assert ('@free(' in body[3]) == bool(heap_slot), (name, helper)
			client_ir, count = re.subn(pattern, lambda m: m[1] + check + m[3] + '}', client_ir, count=1, flags=re.M | re.S)
			assert count == 1
			plans.append(dict(fixture=name, helper=helper, actual=actual, heap_parameter=heap_slot or None, signature=body[1].splitlines()[0], body_sha256=hashlib.sha256(body[3].encode()).hexdigest()))
		client_ir += '\ndeclare void @own_pointer(ptr, i32, i32, i32)\ndeclare void @own_loan(ptr, i32)\n' + entry % ('own_native_entry', main_id)
		for optimize in [False, True]:
			for mode, expected in [('client', trace), ('client-memory', memory_trace)]:
				binary = assemble(client_ir, name + '-' + mode + ('-O2' if optimize else '-O0'), objects[mode], optimize)
				run([*vg, binary] if mode == 'client-memory' else [binary], 42, expected + f'P{pointers}\n', memory=mode == 'client-memory')

				# Resource handles use the existing independent observer and source ABI.
	resource_inputs = [FIXTURES / 'resource.astra', ROOT / 'tests/gen-borrow-1/support.astra', '--vapi', ROOT / 'tests/gen-borrow-1/resources.vapi']
	resource_trace = 'A1:1\nA1:2\nA2:3\nB0\nX1:1\nB0\nX1:2\nB0\nX2:3\nB0\nZ3:0\n'
	resource_obj = output / 'resource.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', ROOT / 'tests/gen-borrow-1/observer.c', '-o', resource_obj])
	resource_binary = output / 'resource'
	run([compiler, *resource_inputs, '--link-object', resource_obj, '-o', resource_binary])
	run([resource_binary], 42, resource_trace)
	run([*vg, resource_binary], 42, resource_trace, memory=True)
	resource_dumps = {stage: run([compiler, '--dump-' + stage, *resource_inputs]) for stage in STAGES}
	for stage, text in resource_dumps.items():
		(output / ('resource.' + stage)).write_text(text)
	main_id = re.search(r'\(function #(\d+) "main" -> int', resource_dumps['ssa'])[1]
	resource_o2 = assemble(resource_dumps['llvm'] + entry % ('main', main_id), 'resource-O2', resource_obj)
	run([resource_o2], 42, resource_trace)
	run([*vg, resource_o2], 42, resource_trace, memory=True)

	# Omitted frees are detected with the standard allocator, without suppressions.
	omitted, count = re.subn(r'^\s*call void @free\(ptr [^\n]*\n', '', saved['early'], flags=re.M)
	assert count > 0
	fault = assemble(omitted, 'omitted-free', objects['memory'])
	run([*vg, fault], 99, diagnostic='definitely lost:')
	# Interposition rejects the duplicate before executing a second host free.
	duplicate, count = re.subn(r'(^\s*call void @free\(ptr [^\n]*\n)', lambda m: m[1] * 2, saved['mixed'], flags=re.M)
	assert count > 0
	fault = assemble(duplicate, 'duplicate-free', objects['observer'])
	run([fault], 98)
	restored = assemble(saved['early'], 'restored', objects['memory'])
	run([*vg, restored], 42, 'I30\nI31\nL30\nB30\nD30\nL31\nB31\nD31\nZ2:0\n', memory=True)
	(output / 'abi.json').write_text(json.dumps(plans, indent=2) + '\n')
	(output / 'identity.json').write_text(json.dumps(dict(compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), positive_programs=len(CASES) + 1, commands=len(rows), standard_allocator_valgrind=sum(x['memory'] for x in rows), fault_controls=2), indent=2) + '\n')
	print(f'{len(CASES) + 1} positive programs; {len(rows)} commands; {sum(x["memory"] for x in rows)} standard-allocator unsuppressed memory checks; 2 detected faults and restored positive')


if __name__ == '__main__':
	main(*sys.argv[1:])
