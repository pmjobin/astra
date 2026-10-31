# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lexical object responsibility, O2 aliasing, original storage and machine audits."""
from pathlib import Path
import json
import os
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'tests/obj-own/fixtures'


def run(argv, status=0, output=None):
	result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert result.returncode == status and not result.stderr and (output is None or result.stdout == output), (argv, result)
	return result.stdout


def audit_ir(name, llvm, ssa):
	for pattern in [r'\b(?:malloc|calloc|realloc|free|atexit|landingpad|personality|invoke)\b', r'refcount|owner[._]active|vtable|typeinfo|\b(?:retain|release)\b', r'llvm\.memcpy|llvm\.memmove']:
		assert not re.search(pattern, llvm), (name, pattern)
	assert llvm.count('alloca %astra.class.') == ssa.count('(object-storage #'), name
	assert 'alloca i1' not in llvm and 'alloca ptr' not in llvm, name
	definitions = re.findall(r'^define internal fastcc ([^\n]+) @(astra\.[\w.]+)\(([^\n]*)\) \{\n(.*?)^}', llvm, re.M | re.S)
	assert definitions
	for result, symbol, parameters, body in definitions:
		assert not re.search(r'\b(?:nonnull|noalias|readonly|byval|sret|dereferenceable|nocapture)\b', parameters), (name, symbol)
		# Owner-only callees need no ObjectStorage. Destruction targets incoming pointers.
	if name in {'consume', 'forward', 'conditional', 'borrow', 'borrow-alias', 'resource', 'multiple', 'vector', 'slice', 'loop', 'loop-move', 'no-deinit', 'empty'}:
		for result, symbol, parameters, body in definitions:
			if 'ptr %p' in parameters:
				assert 'alloca %astra.class.' not in body, (name, symbol)
	if name == 'consume':
		callee = next(body for _, symbol, _, body in definitions if symbol == 'astra.fn.0')
		caller = next(body for _, symbol, _, body in definitions if symbol == 'astra.fn.1')
		assert 'call fastcc void @astra.dtor.0(ptr %p0)' in callee
		assert 'call fastcc void @astra.fn.0(ptr %object0)' in caller
		assert 'br i1 true, label %cleanup0.continue' in caller and 'call fastcc void @astra.dtor.0(ptr null)' in caller
		assert llvm.count('alloca %astra.class.0') == 1
	if name == 'forward':
		forward = next(body for _, symbol, _, body in definitions if symbol == 'astra.fn.1')
		assert 'call fastcc void @astra.fn.0(ptr %p0)' in forward
		assert 'call fastcc void @astra.dtor.0(ptr null)' in forward
	if name == 'conditional':
		assert re.search(r'phi ptr .*null', llvm), name
	if name == 'borrow-alias':
		assert 'call fastcc i32 @astra.fn.0(ptr %object0, ptr %object0)' in llvm
	if name == 'empty':
		assert '%astra.class.0 = type { i8 }' in llvm
	if name == 'no-deinit':
		assert '@astra.dtor.' not in llvm and '(domain object)' in ssa
	return llvm.count('alloca %astra.class.')


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	companion = out/'companion.o'
	run(['cc', '-std=c11', '-Werror', '-Wall', '-Wextra', '-c', ROOT/'tests/obj-life/companion.c', '-o', companion], output='')
	cases = json.loads((FIXTURES/'runtime-cases.json').read_text())
	records = {'runs': [], 'machine': []}
	machine_cases = {'basic', 'consume', 'forward', 'conditional', 'borrow-alias', 'resource', 'order', 'constructor', 'method', 'vector', 'slice', 'empty'}
	for name, case in cases.items():
		source = FIXTURES/f'obj-own-{name}.astra'
		options = ['--vapi', ROOT/'tests/obj-life/fixtures/lifecycle.vapi'] if case['resource'] else []
		status = -signal.SIGILL if case['traps'] else 42
		run([compiler, source, *options, '--link-object', companion, '-o', out/name], output='')
		run([out/name], status, case['stdout'])
		records['runs'].append(dict(name=name, status=status, output=case['stdout']))
		for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
			(out/(name+'.'+stage)).write_text(run([compiler, '--dump-'+stage, source, *([] if stage == 'syntax' else options)]))
		ssa = (out/(name+'.ssa')).read_text(); llvm = (out/(name+'.llvm')).read_text()
		storage_count = audit_ir(name, llvm, ssa)
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		llvm += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		(out/(name+'.ll')).write_text(llvm)
		for mode in ['O2', *(['callable-O2'] if name in machine_cases else [])]:
			optimized = name+'-'+mode
			text = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', llvm, flags=re.M) if mode == 'callable-O2' else llvm
			(out/(optimized+'-input.ll')).write_text(text)
			run(['opt', '-passes=default<O2>', '-S', out/(optimized+'-input.ll'), '-o', out/(optimized+'.ll')], output='')
			run(['opt', '-passes=verify', '-disable-output', out/(optimized+'.ll')], output='')
			run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', out/(optimized+'.ll'), '-o', out/(optimized+'.o')], output='')
			run(['cc', out/(optimized+'.o'), companion, '-o', out/optimized], output='')
			run([out/optimized], status, case['stdout'])
			records['runs'].append(dict(name=optimized, status=status, output=case['stdout']))
			if name in machine_cases:
				(out/(optimized+'.disassembly')).write_text(run(['objdump', '-dr', out/(optimized+'.o')]))
		if name in machine_cases:
			run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', out/(name+'.ll'), '-o', out/(name+'-O0.o')], output='')
			(out/(name+'-O0.disassembly')).write_text(run(['objdump', '-dr', out/(name+'-O0.o')]))
			(out/(name+'-O0.symbols')).write_text(run(['readelf', '-h', '-Ws', out/(name+'-O0.o')]))
			linkage = run(['ldd', out/name]); assert not re.search(r'libglib|libgobject|libLLVM', linkage), name
			(out/(name+'.linkage')).write_text(linkage)
			records['machine'].append(dict(name=name, storage_count=storage_count))
			# A deliberately invalid noalias annotation must break the alias witness at O2.
	unsafe = (out/'borrow-alias-callable-O2-input.ll').read_text().replace('@astra.fn.0(ptr %p0, ptr %p1)', '@astra.fn.0(ptr noalias %p0, ptr noalias %p1)')
	assert 'ptr noalias %p0' in unsafe
	(out/'alias-invalid-noalias-input.ll').write_text(unsafe)
	run(['opt', '-passes=default<O2>', '-S', out/'alias-invalid-noalias-input.ll', '-o', out/'alias-invalid-noalias.ll'], output='')
	run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', out/'alias-invalid-noalias.ll', '-o', out/'alias-invalid-noalias.o'], output='')
	run(['cc', out/'alias-invalid-noalias.o', companion, '-o', out/'alias-invalid-noalias'], output='')
	result = subprocess.run([out/'alias-invalid-noalias'], capture_output=True, text=True)
	assert result.returncode != 42, result
	records['noalias_negative_control'] = dict(status=result.returncode, output=result.stdout)
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['machine'])} machine audits; exact ownership/cleanup/alias checks passed")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
