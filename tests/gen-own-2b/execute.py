# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Finite forwarding: actual original pointers, domains, traces and free faults."""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent
BASE = ROOT / 'tests/gen-own-2a/support.astra'
CASES = {
	'mixed': ('I10 A I20 B20 R10 B10 K10 B10 D10 R20 B20 K20 B20 D20 F20 Z2:1', 11),
	'reverse': ('A I20 I10 R20 B20 K20 B20 D20 F20 B10 R10 B10 K10 B10 D10 Z2:1', 11),
	'inferred': ('A I30 R30 K30 B30 D30 F30 Z1:1', 4),
	'two-hop': ('A I40 O40 R40 B40 K40 B40 D40 F40 Z1:1', 6),
	'long-chain': ('A I45 U45 T45 O45 R45 B45 K45 B45 D45 F45 Z1:1', 8),
	'nodeinit': ('A I50 A I51 R50 B50 K50 B50 F50 R51 B51 K51 B51 F51 Z2:2', 10),
	'derived': ('A I60 O60 R60 B60 K60 B60 d60 D60 F60 Z1:1', 7),
	'conditional': ('A I70 A I71 Q70 K70 B70 D70 F70 Q71 D71 F71 Z2:2', 6),
	'early': ('A I72 A I73 R72 D72 F72 R73 K73 B73 D73 F73 Z2:2', 6),
	'completed': ('A I80 B80 O80 R80 B80 K80 B80 D80 F80 Z1:1', 7),
	'int': ('A I83 R83 K83 D83 F83 Z1:1', 3),
	'bool': ('A I84 R84 K84 D84 F84 Z1:1', 3),
	'u16': ('A I85 R85 K85 D85 F85 Z1:1', 3),
	'f32': ('A I86 R86 K86 D86 F86 Z1:1', 3),
	'f64': ('A I87 R87 K87 D87 F87 Z1:1', 3),
	'child': ('A I82 A I83 O83 R83 B83 K83 B83 D82 F82 F83 Z2:2', 7),
	'dead': ('A I88 D88 F88 Z1:1', 2),
	'paired': ('A I21 A I22 R21 B21 K21 B21 D21 F21 R22 B22 K22 B22 D22 F22 Z2:2', 10),
	'lexical-recursion': ('I89 R89 R89 R89 K89 B89 D89 Z1:0', 6),
}
STAGES = ['semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'llvm']


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows, plans = [], []
	def run(command, status=0, stdout=None, memory=False, diagnostic=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=60,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == status and (stdout is None or p.stdout == stdout)
		if memory:
			valid &= 'ERROR SUMMARY: 0 errors' in p.stderr and 'in use at exit: 0 bytes in 0 blocks' in p.stderr and '(suppressed: 0 from 0)' in p.stderr
		elif diagnostic:
			valid &= diagnostic in p.stderr
		else:
			valid &= not p.stderr
		rows.append(dict(command=command, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, passed=bool(valid)))
		(output / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
		assert valid, rows[-1]
		return p.stdout

	objects = {}
	for name, flags in [('observer', []), ('client', ['-DOWN_CLIENT']), ('memory', ['-DOWN_MEMORY']), ('client-memory', ['-DOWN_MEMORY', '-DOWN_CLIENT'])]:
		obj = output / (name + '.o')
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', *flags, '-c', FIXTURES / 'observer.c', '-o', obj])
		objects[name] = obj
	vg = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all']
	def assemble(ir, stem, companion):
		path, optimized, obj, binary = [output / (stem + suffix) for suffix in ['.ll', '-O2.ll', '.o', '']]
		path.write_text(ir)
		run(['opt', '-passes=default<O2>', '-S', path, '-o', optimized])
		run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj])
		run(['cc', obj, companion, '-o', binary])
		return binary

	saved = {}
	for name, (tokens, pointers) in CASES.items():
		trace = tokens.replace(' ', '\n') + '\n'
		memory_trace = '\n'.join(re.sub(r'Z(\d+):\d+', r'Z\1:0', token) for token in tokens.split() if token != 'A' and not token.startswith('F')) + '\n'
		inputs = [FIXTURES / (name + '.astra'), FIXTURES / 'support.astra', BASE]
		if name == 'reverse': inputs.reverse()
		binary = output / name
		run([compiler, *inputs, '--link-object', objects['observer'], '-o', binary])
		run([binary], 42, trace)
		memory_binary = output / (name + '-memory')
		run([compiler, *inputs, '--link-object', objects['memory'], '-o', memory_binary])
		run([*vg, memory_binary], 42, memory_trace, memory=True)
		dumps = {stage: run([compiler, '--dump-' + stage, *inputs]) for stage in STAGES}
		for stage, text in dumps.items():
			(output / (name + '.' + stage)).write_text(text)
			if stage in ['instances', 'cfg', 'ssa', 'nabi', 'llvm']:
				assert not re.search(r'type-parameter|OWNABLE|ownership-contract|generic-op', text), (name, stage)
		assert dumps['instances'] == run([compiler, '--dump-instances', *inputs])
		ir, ssa = dumps['llvm'], dumps['ssa']
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		entry = '\ndefine i32 @%s(){\n %%r=call fastcc i32 @astra.fn.%s()\n ret i32 %%r\n}\n'
		normal_ir = ir + (entry % ('main', main_id))
		saved[name] = normal_ir
		o2 = assemble(normal_ir, name + '-O2', objects['observer'])
		run([o2], 42, trace)
		memory_o2 = assemble(normal_ir, name + '-memory-O2', objects['memory'])
		run([*vg, memory_o2], 42, memory_trace, memory=True)
		client_ir = ir
		ctor = r'(define internal fastcc void @astra.ctor.\d+\(ptr %this, i32 %p0, i32 %p1[^\n]*\) \{\n\w+:[^\n]*\n)'
		client_ir, count = re.subn(ctor, lambda m: m[1] + '  call void @own_pointer(ptr %this, i32 %p0, i32 %p1, i32 1)\n', client_ir)
		assert count == 6, (name, count)
		instances = re.findall(r'\(generic-instance #(\d+) \(origin #(\d+) "([^"]+)"\) \(type-arguments ([^)]*)\)(?: \(heap-owned-parameter #(\d+)\))?', dumps['instances'])
		assert instances
		keys = [(row[1], row[3], row[4]) for row in instances]
		assert len(set(keys)) == len(keys), name
		if name in ['mixed', 'reverse']:
			pair = ['relay', 'consume'] if name == 'mixed' else ['early_relay', 'late_sink']
			for helper in pair:
				selected = [row for row in instances if row[2] == helper]
				assert len(selected) == 2 and {row[3] for row in selected} == {'Counter'} and {row[4] for row in selected} == {'', '0'}
			origins = {row[2]: int(row[1]) for row in instances}
			assert (origins[pair[0]] < origins[pair[1]]) == (name == 'reverse'), (name, origins)
			assert len([row for row in instances if row[2] == 'loan']) == 1
		if name == 'two-hop':
			assert {(row[2], row[4]) for row in instances if row[2] != 'loan'} == {('outer', '1'), ('relay', '0'), ('consume', '0')}
		for instance, origin, helper, actual, heap_slot in instances:
			ordinal = re.search(r'\(function #(\d+) "astra.gen.' + origin + '.' + instance + '"', ssa)[1]
			pattern = r'(define internal fastcc (?:void|i1|i16|i32|float|double) @astra.fn.' + ordinal + r'\(([^\n]*)\) \{\n\w+:[^\n]*\n)(.*?)^}'
			body = re.search(pattern, ir, re.M | re.S)
			assert body, (name, helper)
			owner = 1 if helper in ['outer', 'relay_int'] else 0
			assert 'ptr %p' + str(owner) in body[2]
			assert not heap_slot or int(heap_slot) == owner
			assert not re.search(r'llvm\.mem(?:cpy|move)|alloca |result.storage', body[0]), (name, helper)
			if helper == 'loan':
				domain = -1
				assert '@free(' not in body[3] and '@astra.dtor' not in body[3]
			else:
				domain = int(bool(heap_slot))
				assert ('@free(' in body[3]) == bool(heap_slot), (name, helper)
			check = f'  call void @own_forward_pointer(ptr %p{owner}, i32 {domain})\n'
			client_ir, count = re.subn(pattern, lambda m: m[1] + check + m[3] + '}', client_ir, count=1, flags=re.M | re.S)
			assert count == 1
			plans.append(dict(fixture=name, helper=helper, type=actual, instance=instance, origin=origin,
				heap_parameter=heap_slot or None, owner_parameter=owner, signature=body[1].splitlines()[0],
				body_sha256=hashlib.sha256(body[3].encode()).hexdigest()))
		client_ir += '\ndeclare void @own_pointer(ptr, i32, i32, i32)\ndeclare void @own_forward_pointer(ptr, i32)\n'
		client_ir += entry % ('own_native_entry', main_id)
		client = assemble(client_ir, name + '-client-O2', objects['client'])
		run([client], 42, trace + f'P{pointers}\n')
		memory_client = assemble(client_ir, name + '-client-memory-O2', objects['client-memory'])
		run([*vg, memory_client], 42, memory_trace + f'P{pointers}\n', memory=True)

		# Mutate the terminal sink in an actual two-hop program. Observers stop a
		# second free before calling the host allocator; its memory path is not run.
	instances = (output / 'two-hop.instances').read_text()
	instance, origin = re.search(r'\(generic-instance #(\d+) \(origin #(\d+) "consume"\) \(type-arguments Counter\) \(heap-owned-parameter #0\)', instances).groups()
	ssa = (output / 'two-hop.ssa').read_text()
	ordinal = re.search(r'\(function #(\d+) "astra.gen.' + origin + '.' + instance + '"', ssa)[1]
	body = re.search(r'^define internal fastcc void @astra.fn.' + ordinal + r'\([^\n]*\) \{\n(.*?)^}', saved['two-hop'], re.M | re.S)
	free = r'^\s+call void @free\(ptr [^\n]+\)(?: #\d+)?\n'
	assert body and len(re.findall(free, body[1], re.M)) == 1
	for name, replacement in [('omitted-free', ''), ('duplicate-free', r'\g<0>\g<0>')]:
		fault = re.sub(free, replacement, body[1], flags=re.M)
		ir = saved['two-hop'][:body.start(1)] + fault + saved['two-hop'][body.end(1):]
		binary = assemble(ir, name, objects['observer'])
		fault_trace = 'A\nI40\nO40\nR40\nB40\nK40\nB40\nD40\n' + ('F40\n' if name == 'duplicate-free' else '')
		run([binary], 98, fault_trace)
		if name == 'omitted-free':
			memory_fault = assemble(ir, name + '-memory', objects['memory'])
			run([*vg, memory_fault], 99, diagnostic='in use at exit:')
			assert re.search(r'in use at exit: [1-9][0-9]* bytes in 1 blocks', rows[-1]['stderr']) and 'ERROR SUMMARY: 1 errors' in rows[-1]['stderr'] and '(suppressed: 0 from 0)' in rows[-1]['stderr']
	inputs = [FIXTURES / 'trap.astra', FIXTURES / 'support.astra', BASE]
	binary = output / 'trap'
	run([compiler, *inputs, '--link-object', objects['observer'], '-o', binary])
	run([binary], -signal.SIGILL, 'A\nI90\nR90\n')
	ir = run([compiler, '--dump-llvm', *inputs]); ssa = run([compiler, '--dump-ssa', *inputs])
	main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
	binary = assemble(ir + (entry % ('main', main_id)), 'trap-O2', objects['observer'])
	run([binary], -signal.SIGILL, 'A\nI90\nR90\n')
	(output / 'abi.json').write_text(json.dumps(plans, indent=2) + '\n')
	identity = dict(compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), cases=CASES,
		checks=len(rows), consumer_plans=len(plans), memory_positives=3*len(CASES), trap_executions=2)
	(output / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
	print(f'{len(rows)} checks: {len(CASES)} native/O2/C-client witnesses, {3*len(CASES)} clean memory runs, free faults and 2 non-unwinding traps')


if __name__ == '__main__':
	main(*sys.argv[1:])
