#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public native Fn values and A28, with independent C and allocation witnesses.

Usage: python3 callable-check.py /absolute/astrac /external/output
All receipts and generated products remain below the given external directory.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
APPS = ROOT / 'examples/language-runtime-4'
LIBS = [ROOT / ('lib/astra/' + name + '.astra') for name in [
	'text/scalar-format', 'hosted/text-ops', 'text/utf8-byte-builder',
	'text/utf8-message', 'collections/bag', 'base/errors', 'hosted/text']]
VG = ['valgrind', '--default-suppressions=no', '--leak-check=full',
	'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99']
NATIVE_DIAGNOSTIC = 'function address requires an exact nonthrowing native copied-scalar signature'
NEGATIVES = {
	'wrong-result': ('i64 apply(int x){return x as i64;}',
	'Fn<int,int> f=apply;return f(1);', NATIVE_DIAGNOSTIC),
	'wrong-input': ('int apply(i64 x){return 1;}',
	'Fn<int,int> f=apply;return f(1);',
	'function address parameter requires exact copied scalar identity'),
	'wrong-target-arity': ('int apply(int x,int y){return x+y;}',
	'Fn<int,int> f=apply;return f(1);', NATIVE_DIAGNOSTIC),
	'wrong-call-arity': ('int apply(int x){return x;}',
	'Fn<int,int> f=apply;return f();',
	'function value invocation requires its exact arity and no type arguments'),
	'wrong-call-input': ('int apply(int x){return x;}',
	'Fn<int,int> f=apply;return f(true);',
	'function value argument requires its exact scalar type'),
	'checked-effect': ('int apply(int x)throws Error{throw new Error("checked");}',
	'Fn<int,int> f=apply;return f(1);', NATIVE_DIAGNOSTIC),
	'foreign-address': ('extern(C) int foreign(int x);',
	'Fn<int,int> f=foreign;return f(1);', "unknown name 'foreign'"),
	'c-boundary-parameter': ('export(C) int escape(Fn<int,int> f){return f(1);}',
	'return 0;', "export(C) parameter type must be 'int' or 'void*'"),
	'c-boundary-result': ('export(C) Fn<int,int> escape(){return null;}',
	'return 0;', "export(C) result type must be 'int', 'void*' or 'void'"),
	'owner-parameter': ('int consume(owned Fn<int,int> f){return 0;}',
	'return 0;', "'owned' parameter requires a native function and an exact nominal handle type"),
	'owner-result': ('owned Fn<int,int> escape(){return null;}',
	'return 0;', "'owned' result requires a nominal handle type"),
	'owner-local': ('int apply(int x){return x;}',
	'owned Fn<int,int> f=apply;return 0;', "OWN-1 supports 'owned' only on local 'void*' declarations"),
	'non-scalar-result': ('Fn<string,int> escape(){return null;}',
	'return 0;', 'Fn result requires a copied numeric scalar or bool'),
	'non-scalar-parameter': ('class Payload{init(){}} Fn<int,Payload> escape(){return null;}',
	'return 0;', 'Fn parameters require copied numeric scalars or bool'),
	'signature-copy': ('int apply(int x){return x;}',
	'Fn<int,int> f=apply;Fn<i64,i64> wrong=f;return 0;',
	"expected initializer of type 'Fn<i64,i64>', found 'Fn<int,int>'"),
	'code-integer-cast': ('int apply(int x){return x;}', 'Fn<int,int> f=apply;return f as int;',
	"unsupported integer conversion source type 'Fn<int,int>'"),
	'data-code-assignment': ('', 'void* pointer=null;Fn<int,int> f=pointer;return 0;',
	"expected initializer of type 'Fn<int,int>', found 'void*'"),
	'over-limit-arity': ('', 'Fn<int,int,int,int,int,int> f=null;return 0;',
	'Fn requires a result and up to four copied scalar parameters'),
	'null-code-address': ('', 'Fn<int,int> f=null;return 0;',
	"expected initializer of type 'Fn<int,int>', found 'void*'"),
	'generic-function-address': ('T identity<T>(T x){return x;}',
	'Fn<int,int> f=identity;return f(1);', NATIVE_DIAGNOSTIC),
	'release-copied-function': ('int apply(int x){return x;}',
	'Fn<int,int> f=apply;release f;return 0;',
	"release operand 'f' must be an owned void* local"),
	'move-copied-function': ('int apply(int x){return x;}',
	'Fn<int,int> f=apply;var other=move f;return 0;',
	"move source 'f' must be an owned void* local"),
}


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def qualify_function_transport(compiler, out, run, product, record, save):
	# Separately approved historical change: Fn copies its exact code identity;
	# the original program returns 1 after generic identity and real invocation.
	name = 'generic-transport-boundary'
	declarations = 'T identity<T>(T x){return x;}int apply(int x){return x;}'
	body = 'Fn<int,int> f=apply;Fn<int,int> other=identity<Fn<int,int>>(f);return other(1);'
	source = out / ('positive-' + name + '.astra')
	source.write_text(declarations + '\nint main(){' + body + '}\n')
	record.setdefault('positive_controls', {})[name] = dict(source=str(source),
		sha256=sha(source), original_native_exit=1, optimization_levels=[0, 1, 2])
	save()
	for stage in ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
		run([compiler, '--dump-' + stage, source], stdout=None)
	for level in [0, 1, 2]:
		binary = out / (name + f'-O{level}')
		run([compiler, f'-O{level}', source, '-o', binary])
		product(binary)
		run([binary], code=1)
		run([*VG, binary], code=1, memory=True)
	return NEGATIVES


def main(compiler, output):
	compiler, out = Path(compiler).resolve(), Path(output).resolve()
	assert not out.is_relative_to(ROOT), 'generated products must be outside source'
	out.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	record = dict(compiler=dict(path=str(compiler), sha256=sha(compiler)),
		commands=[], products={}, source_sha256={}, applications={},
		limitations='Nonthrowing copied-scalar native Fn only; C clients call scalar exports, never cast Fn to C callback; owned closures qualified separately.')
	evidence = out / 'results.json'

	def save():
		evidence.write_text(json.dumps(record, indent=2) + '\n')

	def run(command, code=0, stdout=b'', diagnostic=None, memory=False):
		argv = list(map(str, command))
		started = time.monotonic()
		process = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=180,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		good = process.returncode == code and (stdout is None or process.stdout == stdout)
		if diagnostic is not None:
			good &= (diagnostic.encode() in process.stderr
				and re.search(rb':[0-9]+:[0-9]+: error:', process.stderr) is not None
				and b'internal error' not in process.stderr.lower())
		elif memory:
			good &= all(part in process.stderr for part in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			good &= process.stderr == b''
		record['commands'].append(dict(argv=argv, exit=process.returncode,
			expected_exit=code, stdout_hex=process.stdout.hex(), stderr_hex=process.stderr.hex(),
			expected_stdout_hex=None if stdout is None else stdout.hex(),
			diagnostic=diagnostic, memory=memory, seconds=time.monotonic()-started,
			passed=bool(good)))
		save()
		assert good, record['commands'][-1]
		return process.stdout

	def product(path):
		record['products'][str(path)] = dict(sha256=sha(path), bytes=path.stat().st_size)
		save()

	functions = [HERE / ('callable-' + name + '.astra') for name in ['api', 'functions', 'namespaces']]
	native_sources = [HERE / 'callable-main.astra', *functions]
	app_sources = [APPS / 'function-pipeline.astra', APPS / 'function-pipeline-functions.astra', *LIBS]
	for path in [*native_sources, *app_sources, HERE / 'callable-client.c', Path(__file__).resolve()]:
		record['source_sha256'][str(path.relative_to(ROOT))] = sha(path)
	record['compiler']['version'] = run([compiler, '--version'], stdout=None).decode().strip()
	c_compilers = [cc for cc in ['gcc', 'clang-22'] if shutil.which(cc)]
	if not any('clang' in cc for cc in c_compilers) and shutil.which('clang'):
		c_compilers.append('clang')
	assert len(c_compilers) == 2, 'both independent GCC and Clang are required'
	record['c_compilers'] = {cc: dict(path=shutil.which(cc),
		version=run([cc, '--version'], stdout=None).decode().splitlines()[0]) for cc in c_compilers}

	# A signature must select the correct ABI profile even without any bound
	# free-function declaration incidentally exposing its scalar channels.
	signature_only = out / 'signature-only.astra'
	signature_only.write_text('bool apply(Fn<bool,f64> f){return f(2.5);}'
		'Fn<i64,bool> forward(Fn<i64,bool> f){return f;}\n')
	run([compiler, '--check', signature_only])

	# The unoptimized LLVM must contain a real call through an SSA code address,
	# and no environment allocation. Executable allocation observation is below.
	for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
		ir = run([compiler, '--dump-' + stage, *native_sources], stdout=None)
		(out / ('callable-' + stage + '.txt')).write_bytes(ir)
		if stage == 'llvm':
			assert re.search(rb'\bcall fastcc (?:i1|i32|i64|double) %', ir), 'no indirect typed native call emitted'
			assert not re.search(rb'\bcall [^\n]*@(?:calloc|malloc|realloc)\(', ir), 'Fn allocated an environment'

	for level in [0, 1, 2]:
		for order, sources in enumerate([native_sources, list(reversed(native_sources))]):
			binary = out / f'callable-O{level}-order{order}'
			run([compiler, f'-O{level}', *sources, '-o', binary])
			run([binary])
			product(binary)
			if level in [0, 2] and order == 0:
				run([*VG, binary], memory=True)
		obj = out / f'callable-O{level}.o'
		run([compiler, f'-O{level}', '-c', *functions, '-o', obj])
		product(obj)
		for cc in c_compilers:
			client = out / f'{cc}-callable-O{level}'
			run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', HERE / 'callable-client.c', obj,
				'-Wl,--wrap=malloc,--wrap=calloc,--wrap=realloc', '-o', client])
			run([client], stdout=b'sum=882 wide=8589934593 combined=73014444013 allocations=0\n')
			product(client)
			if level in [0, 2]:
				run([*VG, client], stdout=b'sum=882 wide=8589934593 combined=73014444013 allocations=0\n', memory=True)

	for name, (declarations, body, diagnostic) in qualify_function_transport(compiler, out, run, product, record, save).items():
		source = out / ('negative-' + name + '.astra')
		source.write_text(declarations + '\nint main(){' + body + '}\n')
		extras = [ROOT / 'lib/astra/base/errors.astra'] if name == 'checked-effect' else []
		run([compiler, '--check', source, *extras], code=1, diagnostic=diagnostic)

	providers = []
	for name in ['args', 'text', 'text-ops']:
		obj = out / (name + '-posix.o')
		source = ROOT / f'lib/astra/platform/{name}-posix.c'
		run([c_compilers[0], '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', source, '-o', obj])
		providers.append(obj)
		record['source_sha256'][str(source.relative_to(ROOT))] = sha(source)
	links = [part for obj in providers for part in ['--link-object', obj]]
	cases = [(0, 0), (0, 3), (0, 29), (1, 0), (1, 7), (1, 31)]
	expected_cases = []
	for mode, count in cases:
		units = [(record * 7) % 13 + 1 for record in range(1, count + 1)
			if mode == 0 or record % 5 != 0]
		subtotal = sum(value * (3 if mode == 0 else 2) + (1 if mode == 0 else 7) for value in units)
		expected_cases.append(([mode, count],
			f'records={len(units)}\nsubtotal={subtotal}\nchecksum={subtotal * 1009 + 17}\n'.encode(), 0))
	expected_cases += [([2, 3], b'', 64), ([0, -1], b'', 64), ([0, 10001], b'', 64),
		(['bad', 3], b'', 2), ([], b'', 64)]
	record['applications']['A28'] = dict(name='function-pipeline',
		source_files=[str(p.relative_to(ROOT)) for p in app_sources],
		cases=[dict(args=args, stdout_hex=expected.hex(), exit=code)
		for args, expected, code in expected_cases])
	for level in [0, 1, 2]:
		binary = out / f'function-pipeline-O{level}'
		run([compiler, f'-O{level}', *app_sources, *links, '-o', binary])
		product(binary)
		for args, expected, code in expected_cases:
			run([binary, *args], code=code, stdout=expected)
		for args, expected, code in [expected_cases[0], expected_cases[5], expected_cases[-2]]:
			run([*VG, binary, *args], code=code, stdout=expected, memory=True)
	reversed_binary = out / 'function-pipeline-O2-reversed'
	run([compiler, '-O2', *reversed(app_sources), *links, '-o', reversed_binary])
	product(reversed_binary)
	for args, expected, code in expected_cases[:6]:
		run([reversed_binary, *args], code=code, stdout=expected)
	record['status'] = 'PASS'
	save()
	print(f'PASS native Fn and A28: {len(record["commands"])} command checks; '
		f'{len(record["products"])} products; '
		f'{sum(row["memory"] for row in record["commands"])} clean unsuppressed Valgrind runs')


if __name__ == '__main__':
	main(*sys.argv[1:])
