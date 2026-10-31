# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Incoming heap results: original pointers, independent O2 and memory controls."""
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
	'direct': ('A I80 E80 B80 K80 B80 D80 F80 Z1:1', 7),
	'explicit-owned': ('A I81 E81 B81 K81 B81 D81 F81 Z1:1', 7),
	'inferred': ('A I82 E82 B82 K82 B82 D82 F82 Z1:1', 7),
	'pure': ('A I83 K83 B83 D83 F83 Z1:1', 6),
	'mixed': ('I10 E10 B10 K10 B10 D10 A I20 E20 B20 K20 B20 D20 F20 Z2:1', 14),
	'reverse': ('A I20 E20 B20 K20 B20 D20 F20 I10 E10 B10 K10 B10 D10 Z2:1', 14),
	'nodeinit': ('A I50 A I51 K50 B50 F50 K51 B51 F51 Z2:2', 12),
	'derived': ('A I60 E60 B60 K60 B60 d60 D60 F60 Z1:1', 8),
	'child': ('A I82 A I83 E83 B83 K83 B83 D82 F82 F83 Z2:2', 8),
	'completed': ('A I84 B84 E84 B84 K84 B84 D84 F84 Z1:1', 8),
	'normal-exit': ('A I85 E85 B85 D85 F85 Z1:1', 5),
	'consumer-chain': ('A I86 E86 B86 R86 K86 B86 D86 F86 Z1:1', 8),
	'prefix': ('A I87 E87 B87 K87 B87 D87 F87 Z1:1', 7),
}
STAGES = ['semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'llvm']
RETURNS = {'echo', 'pure', 'early_echo', 'late_echo', 'prefix'}


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows, plans = [], []
	def run(command, status=0, stdout=None, memory=False, diagnostic=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60, env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == status and (stdout is None or p.stdout == stdout)
		if memory:
			valid &= 'ERROR SUMMARY: 0 errors from 0 contexts (suppressed: 0 from 0)' in p.stderr and 'in use at exit: 0 bytes in 0 blocks' in p.stderr
		elif diagnostic: valid &= diagnostic in p.stderr
		else: valid &= not p.stderr
		rows.append(dict(command=command, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, passed=bool(valid)))
		(output / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
		assert valid, rows[-1]
		return p.stdout

	objects = {}
	for name, flags in [('observer', []), ('client', ['-DOWN_CLIENT']), ('memory', ['-DOWN_MEMORY']), ('client-memory', ['-DOWN_MEMORY', '-DOWN_CLIENT'])]:
		objects[name] = output / (name + '.o')
		run(['cc', '-std=c11', '-Werror', '-Wall', '-Wextra', *flags, '-c', FIXTURES / 'observer.c', '-o', objects[name]])
	vg = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all']
	def assemble(ir, stem, companion, optimize=True):
		path, optimized, obj, binary = [output / (stem + suffix) for suffix in ['.ll', '-O2.ll', '.o', '']]
		path.write_text(ir)
		run(['opt', '-passes=default<O2>' if optimize else '-passes=verify', '-S', path, '-o', optimized])
		run(['opt', '-passes=verify', '-disable-output', optimized])
		run(['llc', '-O2' if optimize else '-O0', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj])
		run(['cc', obj, companion, '-o', binary])
		return binary

	saved = {}
	for name, (tokens, pointers) in CASES.items():
		trace = tokens.replace(' ', '\n') + '\n'
		memory_trace = '\n'.join(re.sub(r'Z(\d+):\d+', r'Z\1:0', token) for token in tokens.split() if token != 'A' and not token.startswith('F')) + '\n'
		inputs = [FIXTURES / (name + '.astra'), FIXTURES / 'support.astra', BASE]
		if name == 'reverse': inputs.reverse()
		binary = output / name
		run([compiler, *inputs, '--link-object', objects['observer'], '-o', binary]); run([binary], 42, trace)
		memory_binary = output / (name + '-memory')
		run([compiler, *inputs, '--link-object', objects['memory'], '-o', memory_binary]); run([*vg, memory_binary], 42, memory_trace, memory=True)
		dumps = {stage: run([compiler, '--dump-' + stage, *inputs]) for stage in STAGES}
		for stage, text in dumps.items():
			(output / (name + '.' + stage)).write_text(text)
			if stage in ['instances', 'cfg', 'ssa', 'nabi', 'llvm']: assert not re.search(r'type-parameter|OWNABLE|ownership-contract|generic-op', text)
		assert dumps['instances'] == run([compiler, '--dump-instances', *inputs])
		ir, ssa = dumps['llvm'], dumps['ssa']
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		entry = '\ndefine i32 @%s(){\n %%r=call fastcc i32 @astra.fn.%s()\n ret i32 %%r\n}\n'
		saved[name] = ir + (entry % ('main', main_id))
		o2 = assemble(saved[name], name + '-O2', objects['observer']); run([o2], 42, trace)
		memory_o2 = assemble(saved[name], name + '-memory-O2', objects['memory']); run([*vg, memory_o2], 42, memory_trace, memory=True)
		client_ir, count = re.subn(r'(define internal fastcc void @astra.ctor.\d+\(ptr %this, i32 %p0, i32 %p1[^\n]*\) \{\n\w+:[^\n]*\n)', lambda m: m[1] + '  call void @own_pointer(ptr %this, i32 %p0, i32 %p1, i32 1)\n', ir)
		assert count == 6, count
		instances = re.findall(r'\(generic-instance #(\d+) \(origin #(\d+) "([^"]+)"\) \(type-arguments ([^)]*)\)(?: \(heap-owned-parameter #(\d+)\))?', dumps['instances'])
		assert instances and len({(r[1], r[3], r[4]) for r in instances}) == len(instances)
		if name in ['mixed', 'reverse']:
			helper = 'early_echo' if name == 'mixed' else 'late_echo'
			selected = [r for r in instances if r[2] == helper]
			assert len(selected) == 2 and {r[3] for r in selected} == {'Counter'} and {r[4] for r in selected} == {'', '0'}
			assert [bool(r[4]) for r in selected] == ([False, True] if name == 'mixed' else [True, False])
			# Source declarations actually straddle main, independently of CLI order.
			source = (FIXTURES / (name + '.astra')).read_text()
			assert (source.index('owned T ' + helper) < source.index('int main')) == (name == 'mixed')
		for instance, origin, helper, actual, heap_slot in instances:
			ordinal = re.search(r'\(function #(\d+) "astra.gen.' + origin + '.' + instance + '"', ssa)[1]
			pattern = r'(define internal fastcc (?:void|i32|ptr) @astra.fn.' + ordinal + r'\(([^\n]*)\) \{\n\w+:[^\n]*\n)(.*?)^}'
			body = re.search(pattern, ir, re.M | re.S); assert body, (name, helper)
			owner = 1 if helper == 'prefix' else 0
			assert 'ptr %p' + str(owner) in body[2] and (not heap_slot or int(heap_slot) == owner)
			assert not re.search(r'llvm\.mem(?:cpy|move)|alloca |@(?:calloc|malloc)\(', body[0])
			domain = -1 if helper == 'loan' else int(bool(heap_slot))
			if helper in RETURNS:
				assert ('%result.storage' in body[2]) == (not heap_slot)
				assert re.search(r'ret ptr %p' + str(owner) + r'\b', body[3])
				assert not re.search(r'@(?:free|astra.dtor.\d+)\(ptr %p' + str(owner) + r'\b', body[3])
				modified = re.sub(r'(^\s*ret ptr %p' + str(owner) + r'\b)', f'  call void @own_forward_pointer(ptr %p{owner}, i32 {domain})\n' + r'\1', body[3], flags=re.M)
			else:
				assert '%result.storage' not in body[2]
				modified = body[3]
			client_ir, count = re.subn(pattern, lambda m: m[1] + f'  call void @own_forward_pointer(ptr %p{owner}, i32 {domain})\n' + modified + '}', client_ir, count=1, flags=re.M | re.S)
			assert count == 1
			if helper in RETURNS:
				# Observe the caller's actual PTR result before acquisition/later use.
				client_ir, count = re.subn(r'(^\s*(%\w+) = call fastcc ptr @astra.fn.' + ordinal + r'\([^\n]*\)\n)', lambda m: m[1] + f'  call void @own_forward_pointer(ptr {m[2]}, i32 {domain})\n', client_ir, flags=re.M)
				assert count >= 1
			plans.append(dict(fixture=name, helper=helper, type=actual, heap_parameter=heap_slot or None, owner_parameter=owner, signature=body[1].splitlines()[0], body_sha256=hashlib.sha256(body[3].encode()).hexdigest()))
		client_ir += '\ndeclare void @own_pointer(ptr, i32, i32, i32)\ndeclare void @own_forward_pointer(ptr, i32)\n' + (entry % ('own_native_entry', main_id))
		client_native = assemble(client_ir, name + '-client-native', objects['client'], False); run([client_native], 42, trace + f'P{pointers}\n')
		memory_native = assemble(client_ir, name + '-client-memory-native', objects['client-memory'], False); run([*vg, memory_native], 42, memory_trace + f'P{pointers}\n', memory=True)
		client = assemble(client_ir, name + '-client-O2', objects['client']); run([client], 42, trace + f'P{pointers}\n')
		memory_client = assemble(client_ir, name + '-client-memory-O2', objects['client-memory']); run([*vg, memory_client], 42, memory_trace + f'P{pointers}\n', memory=True)

		# Fault the actual final consumer's release; never run the unsafe second
		# host free. The allocation observer stops that duplicate first.
	ir = saved['direct']
	pattern = r'^define internal fastcc void @astra.fn.\d+\(ptr %p0, i32 %p1\) \{\n(.*?)^}'
	bodies = [m for m in re.finditer(pattern, ir, re.M | re.S) if re.search(r'call void @free\(ptr %p0\)', m[1])]
	assert len(bodies) == 1
	body = bodies[0]; free = r'^\s+call void @free\(ptr %p0\)(?: #\d+)?\n'
	assert len(re.findall(free, body[1], re.M)) == 1
	for name, replacement in [('omitted-free', ''), ('duplicate-free', r'\g<0>\g<0>')]:
		fault = re.sub(free, replacement, body[1], flags=re.M)
		mutated = ir[:body.start(1)] + fault + ir[body.end(1):]
		binary = assemble(mutated, name, objects['observer'])
		run([binary], 98, 'A\nI80\nE80\nB80\nK80\nB80\nD80\n' + ('F80\n' if name == 'duplicate-free' else ''))
		if name == 'omitted-free':
			binary = assemble(mutated, name + '-memory', objects['memory']); run([*vg, binary], 99, diagnostic='in use at exit:')
			assert re.search(r'definitely lost: [1-9][0-9,]* bytes in 1 blocks', rows[-1]['stderr']) and 'ERROR SUMMARY: 1 errors' in rows[-1]['stderr'] and '(suppressed: 0 from 0)' in rows[-1]['stderr']
	run([output / 'direct'], 42, CASES['direct'][0].replace(' ', '\n') + '\n')
	inputs = [FIXTURES / 'trap.astra', FIXTURES / 'support.astra', BASE]
	binary = output / 'trap'; run([compiler, *inputs, '--link-object', objects['observer'], '-o', binary]); run([binary], -signal.SIGILL, 'A\nI90\n')
	ir = run([compiler, '--dump-llvm', *inputs]); ssa = run([compiler, '--dump-ssa', *inputs])
	main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
	binary = assemble(ir + (entry % ('main', main_id)), 'trap-O2', objects['observer']); run([binary], -signal.SIGILL, 'A\nI90\n')
	(output / 'abi.json').write_text(json.dumps(plans, indent=2) + '\n')
	(output / 'identity.json').write_text(json.dumps(dict(compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(), cases=CASES, checks=len(rows), plans=len(plans), memory_positives=4*len(CASES), trap_executions=2), indent=2) + '\n')
	print(f'{len(rows)} commands: {len(CASES)} native/O2/C-client witnesses, {4*len(CASES)} clean normal-allocator memory runs, release faults, 2 nonunwinding traps')


if __name__ == '__main__':
	main(*sys.argv[1:])
