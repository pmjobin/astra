# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lifecycle execution, O2, storage authority, call ordering and machine evidence."""
from pathlib import Path
import json
import os
import re
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT/'tests/obj-life/fixtures'


def run(argv, status=0, output=None):
	result = subprocess.run(list(map(str, argv)), cwd=ROOT, capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
	assert result.returncode == status and not result.stderr and (output is None or result.stdout == output), (argv, result)
	return result.stdout


def audit_ir(name, llvm, ssa):
	for pattern in [r'\b(?:malloc|calloc|realloc|free|atexit|landingpad|personality|invoke|noalias|readonly)\b', r'refcount|gc\.header|vtable|typeinfo|lifecycle\.flag', r'llvm\.memcpy|llvm\.memmove']:
		assert not re.search(pattern, llvm), (name, pattern)
	assert llvm.count('alloca %astra.class.') == ssa.count('(object-storage #'), name
	definitions = re.findall(r'^define internal fastcc ([^\n]+) @(astra\.(?:ctor|dtor)\.\d+)\(([^\n]*)\) \{\n(.*?)^}', llvm, re.M | re.S)
	for result, symbol, parameters, body in definitions:
		assert result == 'void' and parameters.startswith('ptr %this'), (name, symbol)
		assert not re.search(r'icmp (?:eq|ne) ptr %this, null', body), (name, symbol)
		assert not re.search(r'alloca %astra.class.', body) or name in {'deinit', 'constructor-local'}, (name, symbol)
		assert not re.search(r'ret ptr|ret i\d', body), (name, symbol)
		if 'dtor' in symbol:
			assert parameters == 'ptr %this', (name, symbol)
			# Every lifecycle call receives an original alloca, even after null/rebind.
	calls = re.findall(r'call fastcc void @astra\.(ctor|dtor)\.(\d+)\(ptr (%\w+)', llvm)
	assert all(storage.startswith('%object') for _, _, storage in calls), (name, calls)
	if name in {'alias', 'null-rebind', 'brace'}:
		assert [s for kind, _, s in calls if kind == 'dtor'] == ['%object0']*(2 if name == 'alias' else 1)
	if name == 'rebind':
		assert [s for kind, _, s in calls if kind == 'dtor'] == ['%object2', '%object1', '%object0']*2
	if name == 'empty':
		assert '%astra.class.0 = type { i8 }' in llvm and 'icmp eq ptr %object0, %object1' in llvm
		assert [s for kind, _, s in calls if kind == 'dtor'] == ['%object1', '%object0']*2
	if name == 'init-unreachable':
		constructor = next(body for _, symbol, _, body in definitions if 'ctor' in symbol)
		assert not re.search(r'load i32', constructor), constructor
	if name == 'return':
		main = re.search(r'define internal fastcc i32 @astra.fn.0\(\) \{(.*?)^}', llvm, re.M | re.S)[1]
		assert main.index('load i32') < main.index('@life_record(i32 82') < main.index('@astra.dtor.0') < main.index('ret i32')
	if name == 'order':
		main = re.search(r'define internal fastcc void @astra.fn.0\(\) \{(.*?)^}', llvm, re.M | re.S)[1]
		sequence = re.findall(r'call (?:fastcc )?void @(astra.dtor.\d+|life_destroy)\(ptr ([^\)]+)', main)
		assert [target for target, _ in sequence] == ['astra.dtor.0']*3+['life_destroy','astra.dtor.0','life_destroy'], sequence
	return len(definitions)


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	companion = out/'companion.o'
	run(['cc', '-std=c11', '-Werror', '-Wall', '-Wextra', '-c', ROOT/'tests/obj-life/companion.c', '-o', companion], output='')
	cases = json.loads((FIXTURES/'runtime-cases.json').read_text())
	records = {'runs': [], 'machine': []}
	for name, case in cases.items():
		source = FIXTURES/f'obj-life-{name}.astra'
		options = ['--vapi', FIXTURES/'lifecycle.vapi'] if case['resource'] else []
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
		machine = name in {'init', 'alias', 'null-rebind', 'rebind', 'return', 'order', 'loop', 'return-loop', 'empty', 'vector', 'slice', 'owned'}
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
			records['machine'].append(dict(name=name, lifecycle_functions=count, storage_count=ssa.count('(object-storage #')))
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f"{len(records['runs'])} executions; {len(records['machine'])} machine audits; exact lifecycle storage/call/order checks passed")


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
