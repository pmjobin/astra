# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Owned results: runtime traces, pointer identity, O2, physical signatures and objects."""
from pathlib import Path
import json
import os
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/obj-ret/fixtures'
MACHINE = {'basic', 'null', 'param', 'forward', 'recursive', 'vector', 'slice', 'owned', 'method', 'empty', 'forward-param'}


def run(argv, status=0, output=None):
	result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert result.returncode == status and not result.stderr and (output is None or result.stdout == output), (argv, result)
	return result.stdout


def audit(name, llvm, ssa, nabi):
	for pattern in [r'\b(?:malloc|calloc|realloc|free|atexit|landingpad|personality|invoke)\b', r'refcount|result[._]active|storage[._]kind|allocator[._]tag', r'llvm\.memcpy|llvm\.memmove', r'alloca (?:ptr|i1)\b']:
		assert not re.search(pattern, llvm), (name, pattern)
	assert llvm.count('alloca %astra.class.') == len(re.findall(r'^\t\t\((?:object-storage|candidate-storage) #', ssa, re.M)), name
	assert '(result-storage PTR first caller-provided)' in nabi
	assert 'object-result-v' not in nabi
	definitions = re.findall(r'^define internal fastcc ([^\n]+) @(astra\.[\w.]+)\(([^\n]*)\) \{\n(.*?)^}', llvm, re.M | re.S)
	factories = []
	for result, symbol, parameters, body in definitions:
		assert not re.search(r'\b(?:nonnull|noalias|readonly|byval|sret|dereferenceable|nocapture)\b', parameters), (name, symbol)
		if 'ptr %result.storage' in parameters:
			assert parameters.startswith('ptr %result.storage') and result == 'ptr', (name, symbol)
			assert 'alloca %astra.class.0' not in body, (name, symbol)
			if name not in {'life', 'forward-consume-local'}:
				assert 'alloca %astra.class.' not in body, (name, symbol)
			factories.append(dict(symbol=symbol, signature=parameters, result=result))
	assert factories
	if name == 'basic':
		assert llvm.count('alloca %astra.class.') == 1
		factory = next(body for _, symbol, _, body in definitions if symbol == 'astra.fn.0')
		assert 'call fastcc void @astra.ctor.0(ptr %result.storage, i32 %p0)' in factory and 'ret ptr %result.storage' in factory
		caller = next(body for _, symbol, _, body in definitions if symbol == 'astra.fn.1')
		assert '@astra.fn.0(ptr %object0, i32 42)' in caller
		assert '@astra.dtor.0(ptr %v0)' in caller and '@astra.dtor.0(ptr %object0)' not in caller
	if name in {'forward', 'recursive', 'forward-param'}:
		assert re.search(r'call fastcc ptr @astra.fn.\d+\(ptr %result.storage', llvm), name
	if name == 'param':
		factory = next(body for _, symbol, _, body in definitions if symbol == 'astra.fn.0')
		assert 'ret ptr %p0' in factory and '@astra.dtor.0(ptr null)' in factory
	if name == 'empty':
		assert '%astra.class.0 = type { i8 }' in llvm and 'icmp eq ptr' in llvm
	if name == 'no-deinit':
		assert '@astra.dtor.' not in llvm
	if name == 'vector':
		assert '(native-abi vector-v4' in nabi and 'ptr %result.storage, <4 x float> %p0, <8 x i16> %p1' in llvm
	if name == 'slice':
		assert '(native-abi slice-v5' in nabi and 'ptr %result.storage, ptr %p0.base, i32 %p0.length' in llvm
	return factories


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	companion = out / 'companion.o'
	run(['cc', '-std=c11', '-Werror', '-Wall', '-Wextra', '-c', ROOT/'tests/obj-life/companion.c', '-o', companion], output='')
	cases = json.loads((FIXTURES/'runtime-cases.json').read_text())
	records = dict(runs=[], machine=[], factories={})
	for name, case in cases.items():
		source = FIXTURES / f'obj-ret-{name}.astra'
		options = ['--vapi', ROOT/'tests/obj-life/fixtures/lifecycle.vapi'] if case['resource'] else []
		status = -signal.SIGILL if case['traps'] else 42
		run([compiler, source, *options, '--link-object', companion, '-o', out/name], output='')
		run([out/name], status, case['stdout'])
		records['runs'].append(dict(name=name, status=status, output=case['stdout']))
		for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
			(out/(name+'.'+stage)).write_text(run([compiler, '--dump-'+stage, source, *([] if stage == 'syntax' else options)]))
		ssa = (out/(name+'.ssa')).read_text()
		llvm = (out/(name+'.llvm')).read_text()
		records['factories'][name] = audit(name, llvm, ssa, (out/(name+'.nabi')).read_text())
		main_id = re.search(r'\(function #(\d+) "main" -> int', ssa)[1]
		llvm += '\ndefine i32 @main() {\n\t%result = call fastcc i32 @astra.fn.'+main_id+'()\n\tret i32 %result\n}\n'
		(out/(name+'.ll')).write_text(llvm)
		for mode in ['O2', *(['callable-O2'] if name in MACHINE else [])]:
			optimized = name+'-'+mode
			text = re.sub(r'^define internal fastcc ([^\n]+) \{$', r'define fastcc \1 noinline {', llvm, flags=re.M) if mode == 'callable-O2' else llvm
			(out/(optimized+'-input.ll')).write_text(text)
			run(['opt', '-passes=default<O2>', '-S', out/(optimized+'-input.ll'), '-o', out/(optimized+'.ll')], output='')
			run(['opt', '-passes=verify', '-disable-output', out/(optimized+'.ll')], output='')
			run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', out/(optimized+'.ll'), '-o', out/(optimized+'.o')], output='')
			run(['cc', out/(optimized+'.o'), companion, '-o', out/optimized], output='')
			run([out/optimized], status, case['stdout'])
			records['runs'].append(dict(name=optimized, status=status, output=case['stdout']))
			if name in MACHINE:
				(out/(optimized+'.disassembly')).write_text(run(['objdump', '-dr', out/(optimized+'.o')]))
		if name in MACHINE:
			run(['llc', '-O0', '-filetype=obj', '-relocation-model=pic', out/(name+'.ll'), '-o', out/(name+'-O0.o')], output='')
			(out/(name+'-O0.disassembly')).write_text(run(['objdump', '-dr', out/(name+'-O0.o')]))
			(out/(name+'-O0.symbols')).write_text(run(['readelf', '-h', '-Ws', out/(name+'-O0.o')]))
			linkage = run(['ldd', out/name])
			assert not re.search(r'libglib|libgobject|libLLVM', linkage), name
			(out/(name+'.linkage')).write_text(linkage)
			records['machine'].append(name)
			# Observe the transferred pointer from a test-only caller without retaining
			# a source-language borrow across the consuming call (PARAM-BORROW-1).
	ir = (out/'param-identity.llvm').read_text()
	ssa = (out/'param-identity.ssa').read_text()
	identity = re.search(r'\(function #(\d+) "identity"', ssa)[1]
	ir += f"""
define i32 @main() {{
	%storage = alloca %astra.class.0, align 8
	%unused = alloca %astra.class.0, align 8
	store i32 7, ptr %unused
	call fastcc void @astra.ctor.0(ptr %storage, i32 42)
	%result = call fastcc ptr @astra.fn.{identity}(ptr %unused, ptr %storage)
	%same = icmp eq ptr %result, %storage
	%value = load i32, ptr %result
	%intact = icmp eq i32 %value, 42
	%candidate = load i32, ptr %unused
	%untouched = icmp eq i32 %candidate, 7
	%a = and i1 %same, %intact
	%ok = and i1 %a, %untouched
	call fastcc void @astra.dtor.0(ptr %result)
	%status = select i1 %ok, i32 42, i32 1
	ret i32 %status
}}
"""
	for mode in ['O0', 'O2']:
		stem = 'param-identity-storage-'+mode
		inp = out/(stem+'-input.ll'); inp.write_text(ir)
		optimized = out/(stem+'.ll'); obj = out/(stem+'.o'); exe = out/stem
		run(['opt', '-passes=verify' if mode == 'O0' else '-passes=default<O2>', '-S', inp, '-o', optimized], output='')
		run(['llc', '-O0' if mode == 'O0' else '-O2', '-filetype=obj', '-relocation-model=pic', optimized, '-o', obj], output='')
		run(['cc', obj, companion, '-o', exe], output='')
		run([exe], 42, cases['param-identity']['stdout'])
		records['runs'].append(dict(name=stem, status=42, output=cases['param-identity']['stdout']))
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['machine'])} machine audits; caller storage, owner identity and cleanup verified")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
