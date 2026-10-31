# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual source/native/O2 loans, independent C client and cleanup fault controls."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/gen-borrow-1'
CASES = {
	'resource': ('A1:1\nA2:2\nB0\nF0\nW0\nX1:1\nW0\nX2:2\nZ2:0\n', 7),
	'class': ('C10\nC20\nB0\nF0\nW0\nD10\nR20\nD20\nZ0:2\n', 6),
	'caller': ('C30\nB0\nW0\nD30\nZ0:1\n', 4),
	'null': ('N0\nN0\nN0\nN0\nZ0:0\n', 6),
	'empty': ('C1\nC1\nB0\nF0\nZ0:0\n', 4),
	'derived': ('C40\nB0\nd40\nD40\nZ0:2\n', 2),
	'control-flow': ('A1:1\nF0\nB0\nF0\nW0\nX1:1\nZ1:0\n', 7),
	'completed': ('A1:1\nB0\nX1:1\nZ1:0\n', 1),
	'scalar': ('A1:1\nB0\nX1:1\nZ1:0\n', 1),
}
STAGES = ['semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	if output.is_relative_to(ROOT):
		raise ValueError('outputs must be outside the source repository')
	output.mkdir(parents=True, exist_ok=True)
	rows, abi = [], []

	def run(command, status=0, stdout=None, memory=False, diagnostic=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == status and (stdout is None or stdout == p.stdout)
		if memory:
			valid = valid and 'ERROR SUMMARY: 0 errors' in p.stderr and 'in use at exit: 0 bytes in 0 blocks' in p.stderr and '(suppressed: 0 from 0)' in p.stderr
		elif diagnostic:
			valid = valid and diagnostic in p.stderr
		else:
			valid = valid and not p.stderr
		rows.append(dict(command=command, exit=p.returncode, stdout=p.stdout, stderr=p.stderr, passed=valid))
		(output / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
		if not valid:
			raise AssertionError(rows[-1])
		return p.stdout

	objects = {}
	for name, flags in [('observer', []), ('client', ['-DDESIGN_CLIENT'])]:
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

	saved_ir = {}
	for name, (trace, pointers) in CASES.items():
		inputs = [FIXTURES / (name + '.astra'), FIXTURES / 'support.astra', '--vapi', FIXTURES / 'resources.vapi']
		binary = output / name
		run([compiler, *inputs, '--link-object', objects['observer'], '-o', binary])
		run([binary], 42, trace)
		dumps = {stage: run([compiler, '--dump-' + stage, *inputs]) for stage in STAGES}
		for stage, text in dumps.items():
			(output / (name + '.' + stage)).write_text(text)
			if stage in ['instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
				assert not re.search(r'type-parameter|OWNABLE|ownership-contract|generic-op', text), (name, stage)
		for stage in ['core', 'llvm']:
			assert dumps[stage] == run([compiler, '--dump-' + stage, *inputs])
		ir, ssa = dumps['llvm'], dumps['ssa']
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		entry = '\n%sdefine i32 @%s() {\n %%r = call fastcc i32 @astra.fn.%s()\n ret i32 %%r\n}\n'
		normal_ir = ir + (entry % ('', 'main', main_id))
		saved_ir[name] = normal_ir
		o2 = assemble(normal_ir, name + '-O2', objects['observer'])
		run([o2], 42, trace)
		run([*vg, o2], 42, trace, memory=True)

		# An independently compiled C main calls the actual generated native
		# source program. Test-only entry observations check original addresses;
		# they change no ownership, allocation, cleanup or source-call operation.
		class_kinds = {n: 10 + int(i) for i, n in re.findall(r'\(class #(\d+) "([^"]+)"', ssa)}
		client_ir = ir
		for cname, kind in class_kinds.items():
			ordinal = kind - 10
			pattern = r'(define internal fastcc void @astra.ctor.' + str(ordinal) + r'\(ptr %this[^\n]*\) \{\n\w+:[^\n]*\n)'
			client_ir, count = re.subn(pattern, lambda m: m[1] + f'  call void @design_register(ptr %this, i32 {kind})\n', client_ir)
			assert count == 1, (name, cname)
		for row in re.finditer(r'\(generic-instance #(\d+) \(origin #(\d+) "(leaf|forward)"\) \(type-arguments ([^)]*)\)', dumps['instances']):
			instance, origin, helper, actual = row.groups()
			ordinal = re.search(r'\(function #(\d+) "astra.gen.' + origin + '.' + instance + '"', ssa)[1]
			pattern = r'(define internal fastcc i32 @astra.fn.' + ordinal + r'\(ptr %p0, i32 %p1\) \{\n\w+:[^\n]*\n)'
			match = re.search(pattern + r'(.*?)^}', ir, re.M | re.S)
			assert match and not re.search(r'@(?:drop_[rs]|calloc|free|astra\.dtor)|llvm\.mem(?:cpy|move)|alloca ', match[2]), (name, helper)
			kind = {'R': 1, 'S': 2}.get(actual, class_kinds.get(actual))
			assert kind is not None
			client_ir, count = re.subn(pattern, lambda m: m[1] + f'  call void @design_borrow(ptr %p0, i32 {kind})\n', client_ir)
			assert count == 1
			abi.append(dict(fixture=name, helper=helper, type=actual, signature=match[1].splitlines()[0], body_sha256=hashlib.sha256(match[2].encode()).hexdigest()))
		client_ir += '\ndeclare void @design_register(ptr, i32)\ndeclare void @design_borrow(ptr, i32)\n'
		client_ir += entry % ('', 'loan_native_entry', main_id)
		client = assemble(client_ir, name + '-client-O2', objects['client'])
		run([client], 42, trace + f'P{pointers}\n')
		run([*vg, client], 42, trace + f'P{pointers}\n', memory=True)

		# Isolated falsified cleanup in otherwise generated code: omitted cleanup
		# leaks an actual allocation; duplicate cleanup is caught before a second
		# free by the independent observer's exact live-handle/nominal check.
	pattern = r'^\s+call void @drop_r\(ptr [^\n]+\)\n'
	instances = (output / 'resource.instances').read_text()
	ssa = (output / 'resource.ssa').read_text()
	instance, origin = re.search(r'\(generic-instance #(\d+) \(origin #(\d+) "dispose"\) \(type-arguments R\)', instances).groups()
	ordinal = re.search(r'\(function #(\d+) "astra.gen.' + origin + '.' + instance + '"', ssa)[1]
	body = re.search(r'^define internal fastcc void @astra.fn.' + ordinal + r'\([^\n]*\) \{\n(.*?)^}', saved_ir['resource'], re.M | re.S)
	assert body
	match = re.search(pattern, saved_ir['resource'][body.start():body.end()], re.M)
	assert match
	start, end = body.start() + match.start(), body.start() + match.end()
	leaking = saved_ir['resource'][:start] + saved_ir['resource'][end:]
	doubled = saved_ir['resource'][:start] + match[0] * 2 + saved_ir['resource'][end:]
	for label, modified in [('omitted-cleanup', leaking), ('double-cleanup', doubled)]:
		binary = assemble(modified, label, objects['observer'])
		run([binary], 98, diagnostic='observer violation')
		if label == 'omitted-cleanup':
			run([*vg, binary], 99, diagnostic='8 bytes in 1 blocks')
	(output / 'abi.json').write_text(json.dumps(abi, indent=2) + '\n')
	(output / 'identity.json').write_text(json.dumps({
		'compiler': str(compiler), 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
		'cases': CASES, 'checks': len(rows), 'borrower_signatures': len(abi),
		'fault_controls': ['omitted cleanup: observer and Valgrind detected', 'double cleanup: observer detected before second free'],
	}, indent=2) + '\n')
	print(f'{len(rows)} checks; {len(CASES)} source/native, {len(CASES)} O2, {len(CASES)} independent C-client/O2 executions; {len(CASES)*2} unsuppressed Valgrind positives; 2 cleanup fault controls')


if __name__ == '__main__':
	main(*sys.argv[1:])
