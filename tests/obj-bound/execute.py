# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Borrowed object execution, null/order/alias/cleanup audits and x86-64 evidence."""
from pathlib import Path
import json
import os
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'tests/obj-bound/fixtures'


def run(argv, status=0, output=None):
	result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert result.returncode == status and not result.stderr and (output is None or result.stdout == output), (argv, result)
	return result.stdout


def audit_ir(name, llvm, ssa):
	for pattern in [r'\b(?:malloc|calloc|realloc|free|atexit|landingpad|personality|invoke)\b', r'refcount|borrow[._]token|type[._]tag|vtable|typeinfo', r'llvm\.memcpy|llvm\.memmove']:
		assert not re.search(pattern, llvm), (name, pattern)
	assert llvm.count('alloca %astra.class.') == ssa.count('(object-storage #'), name
	definitions = re.findall(r'^define internal fastcc ([^\n]+) @(astra\.[\w.]+)\(([^\n]*)\) \{\n(.*?)^}', llvm, re.M | re.S)
	assert definitions
	borrowed = 0
	for result, symbol, parameters, body in definitions:
		assert not re.search(r'\b(?:nonnull|noalias|readonly|byval|sret|dereferenceable|nocapture)\b', parameters), (name, symbol)
		if 'ptr %p' not in parameters:
			continue
		borrowed += 1
		assert 'alloca %astra.class.' not in body and '@astra.dtor.' not in body, (name, symbol)
		assert 'alloca ptr' not in body or name in {'owned', 'owned-trap'}, (name, symbol)
		# Lifecycle actions still receive original caller storage, never a parameter or alias slot.
	calls = re.findall(r'call fastcc void @astra\.(ctor|dtor)\.(\d+)\(ptr (%\w+)', llvm)
	assert all(storage.startswith('%object') for _, _, storage in calls), (name, calls)
	if name == 'mutate':
		assert [storage for kind, _, storage in calls if kind == 'dtor'] == ['%object0']
	if name in {'life', 'alias'}:
		assert {storage for kind, _, storage in calls if kind == 'dtor'} == {'%object0'}
	if name == 'empty':
		assert '%astra.class.0 = type { i8 }' in llvm and llvm.count('alloca %astra.class.0') == 2
	if name == 'null':
		assert '@llvm.trap' not in llvm and 'ptr null' in llvm
	if name in {'basic', 'mutate', 'alias', 'null-field', 'null-write', 'null-method'}:
		assert 'icmp eq ptr %p0, null' in llvm and '@llvm.trap' in llvm
	if name in {'null-write', 'null-method'}:
		callee = next(body for _, symbol, _, body in definitions if symbol == 'astra.fn.1')
		assert callee.index('icmp eq ptr %p0, null') < callee.index('call fastcc i32 @astra.fn.0()')
	return borrowed


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	companion = out/'companion.o'
	run(['cc', '-std=c11', '-Werror', '-Wall', '-Wextra', '-c', ROOT/'tests/obj-life/companion.c', '-o', companion], output='')
	cases = json.loads((FIXTURES/'runtime-cases.json').read_text())
	records = {'runs': [], 'machine': []}
	for name, case in cases.items():
		source = FIXTURES/f'obj-bound-{name}.astra'
		options = ['--vapi', ROOT/'tests/obj-life/fixtures/lifecycle.vapi'] if case['resource'] else []
		status = -signal.SIGILL if case['traps'] else 42
		stem = out/name
		run([compiler, source, *options, '--link-object', companion, '-o', stem], output='')
		run([stem], status, case['stdout'])
		records['runs'].append(dict(name=name, status=status, output=case['stdout']))
		for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
			text = run([compiler, '--dump-'+stage, source, *([] if stage == 'syntax' else options)])
			(out/(name+'.'+stage)).write_text(text)
		ssa = (out/(name+'.ssa')).read_text()
		llvm = (out/(name+'.llvm')).read_text()
		count = audit_ir(name, llvm, ssa)
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		llvm += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		(out/(name+'.ll')).write_text(llvm)
		machine = name in {'basic', 'mutate', 'method', 'alias', 'life', 'constructor', 'empty', 'vector', 'slice', 'owned'}
		for mode in ['O2', *(['callable-O2'] if machine else [])]:
			optimized = name+'-'+mode
			text = llvm
			if mode == 'callable-O2':
				text = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', text, flags=re.M)
			(out/(optimized+'-input.ll')).write_text(text)
			run(['opt', '-passes=default<O2>', '-S', out/(optimized+'-input.ll'), '-o', out/(optimized+'.ll')], output='')
			run(['opt', '-passes=verify', '-disable-output', out/(optimized+'.ll')], output='')
			run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', out/(optimized+'.ll'), '-o', out/(optimized+'.o')], output='')
			run(['cc', out/(optimized+'.o'), companion, '-o', out/optimized], output='')
			run([out/optimized], status, case['stdout'])
			records['runs'].append(dict(name=optimized, status=status, output=case['stdout']))
			if machine:
				(out/(optimized+'.disassembly')).write_text(run(['objdump', '-dr', out/(optimized+'.o')]))
		if machine:
			run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', out/(name+'.ll'), '-o', out/(name+'-O0.o')], output='')
			(out/(name+'-O0.disassembly')).write_text(run(['objdump', '-dr', out/(name+'-O0.o')]))
			(out/(name+'-O0.symbols')).write_text(run(['readelf', '-h', '-Ws', out/(name+'-O0.o')]))
			linkage = run(['ldd', stem]); assert not re.search(r'libglib|libgobject|libLLVM', linkage), name
			(out/(name+'.linkage')).write_text(linkage)
			records['machine'].append(dict(name=name, borrowed_definitions=count, storage_count=ssa.count('(object-storage #')))
	unsafe = (out/'alias-callable-O2-input.ll').read_text().replace('@astra.fn.0(ptr %p0, ptr %p1)', '@astra.fn.0(ptr noalias %p0, ptr noalias %p1)')
	assert 'ptr noalias %p0' in unsafe
	(out/'alias-invalid-noalias-input.ll').write_text(unsafe)
	run(['opt', '-passes=default<O2>', '-S', out/'alias-invalid-noalias-input.ll', '-o', out/'alias-invalid-noalias.ll'], output='')
	run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', out/'alias-invalid-noalias.ll', '-o', out/'alias-invalid-noalias.o'], output='')
	run(['cc', out/'alias-invalid-noalias.o', companion, '-o', out/'alias-invalid-noalias'], output='')
	unsafe_result = subprocess.run([out/'alias-invalid-noalias'], capture_output=True, text=True)
	assert unsafe_result.returncode != 42, unsafe_result
	records['noalias_negative_control'] = dict(status=unsafe_result.returncode, output=unsafe_result.stdout)
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['machine'])} machine audits; exact object parameter/alias/cleanup/order checks passed")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
