#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public closure transport, captures, rollback, ABI and memory witnesses."""
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
HEADER = 'class Env{int bias;init(int bias){this.bias=bias;}} int apply(borrowed Env env,int x){return env.bias+x;}'
BIND = 'var env=new Env(10);var f=closure_bind(move env,apply);'
NEGATIVES = {
	'lexical-environment': (HEADER, 'var env=Env.init(10);var f=closure_bind(move env,apply);return 0;', 'closure_bind environment requires explicit move'),
	'borrowed-environment': (HEADER+'void bad(borrowed Env env){var f=closure_bind(move env,apply);}', 'return 0;', 'nontransferable'),
	'double-environment-capture': (HEADER, BIND+'var g=closure_bind(move env,apply);return 0;', "use of moved owned value 'env'"),
	'unowned-null-local': (HEADER, 'Closure<Env,int,int> f=null;return closure_invoke(f,1);', 'closure_invoke requires a live exact typed closure'),
	'raw-environment-field': ('class Env{void* context;init(){this.context=null;}} int apply(borrowed Env env,int x){return x;}', 'var env=new Env();var f=closure_bind(move env,apply);return 0;', 'closure environment and owned child captures cannot contain unmanaged raw or typed pointers'),
	'raw-child-field': ('class Child{void* context;init(){this.context=null;}} class Env{private owned Child child;init(owned Child child){this.child=move child;}} int apply(borrowed Env env,int x){return x;}', 'var child=new Child();var env=new Env(move child);var f=closure_bind(move env,apply);return 0;', 'closure environment and owned child captures cannot contain unmanaged raw or typed pointers'),
	'copy-closure': (HEADER, BIND+'Closure<Env,int,int> copy=f;return 0;', "owned local 'f' cannot be copied"),
	'call-after-move': (HEADER, BIND+'var moved=move f;return closure_invoke(f,1);', "use of moved owned value 'f'"),
	'call-after-release': (HEADER, BIND+'release f;return closure_invoke(f,1);', "use of released owned value 'f'"),
	'wrong-code-environment': (HEADER+'class Other{init(){}} int other(borrowed Other env,int x){return x;}', 'var env=new Env(10);var f=closure_bind(move env,other);return 0;', 'closure code requires an exact nonthrowing native function'),
	'wrong-call-type': (HEADER, BIND+'return closure_invoke(f,true);', 'closure invocation argument requires its exact scalar signature type'),
	'wrong-call-arity': (HEADER, BIND+'return closure_invoke(f);', 'closure_invoke requires a live exact typed closure'),
	'checked-code': ('class Env{init(){}} int apply(borrowed Env env,int x)throws Error{throw new Error("checked");}', 'var env=new Env();var f=closure_bind(move env,apply);return 0;', 'closure code requires an exact nonthrowing native function'),
	'foreign-code': ('class Env{init(){}} extern(C) int foreign(int x);', 'var env=new Env();var f=closure_bind(move env,foreign);return 0;', 'closure code requires an exact nonthrowing native function'),
	'consume-during-call': (HEADER+'int consume(owned Closure<Env,int,int> f){return 1;}', BIND+'return closure_invoke(f,consume(move f));', 'forbids moving its backing'),
	'scalar-code-cast': ('class Env{init(){}}', 'owned Closure<Env,int,int> f=0 as Closure<Env,int,int>;return 0;', "expected ';' after local declaration"),
	'owned-result-channel': ('class Env{init(){}}', 'Closure<Env,string,int> f=null;return 0;', 'Closure requires an exact concrete nongeneric Class environment and copied scalar signature'),
	'borrow-escape': (HEADER+'owned Closure<Env,int,int> escape(borrowed Closure<Env,int,int> f){return move f;}', 'return 0;', 'owned nominal handle local or parameter'),
}


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def a29_trace(count, early):
	limit = min(count, 2) if early else count
	lines = ['event=3:3', 'event=1:10', 'event=5:10']
	lines += [f'item={item} amount={item * 3}' for item in range(1, limit + 1)]
	lines += ['event=6:10', 'event=4:3', 'event=2:10', f'event=7:{3 * limit * (limit + 1) // 2}']
	return ('\n'.join(lines) + '\n').encode()


def a30_trace(mode):
	lines = ['event=11:30']
	if mode:
		lines += ['event=13:7', 'event=15:1']
		if mode == 2:
			lines += ['event=17:42']
		lines += ['event=16:1', 'event=14:7']
	lines += [['before capture', 'after capture and upgrade', 'after invocation'][mode],
		'event=18:30', 'event=12:30', 'expired']
	return ('\n'.join(lines) + '\n').encode()


def main(compiler, output):
	compiler, out = Path(compiler).resolve(), Path(output).resolve()
	assert not out.is_relative_to(ROOT), 'generated products must remain outside source'
	out.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	record = dict(compiler=dict(path=str(compiler), sha256=sha(compiler)), commands=[], products={},
		applications={}, source_sha256={},
		limitations='Exact nonpolymorphic nongeneric heap Class environment; nonthrowing copied scalar native signature; checked caller unwind only; synchronous call borrowing; no retained C callbacks or inferred captures.')

	def save():
		(out / 'results.json').write_text(json.dumps(record, indent=2) + '\n')

	def run(command, code=0, stdout=b'', diagnostic=None, memory=False):
		argv = list(map(str, command)); started = time.monotonic()
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=180,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		good = result.returncode == code and (stdout is None or result.stdout == stdout)
		if diagnostic:
			good &= diagnostic.encode() in result.stderr and re.search(rb':[0-9]+:[0-9]+: error:', result.stderr) is not None and b'internal error' not in result.stderr.lower()
		elif memory:
			good &= all(part in result.stderr for part in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			good &= not result.stderr
		record['commands'].append(dict(argv=argv, exit=result.returncode, expected_exit=code,
			stdout_hex=result.stdout.hex(), stderr_hex=result.stderr.hex(),
			expected_stdout_hex=None if stdout is None else stdout.hex(), diagnostic=diagnostic,
			memory=memory, seconds=time.monotonic() - started, passed=bool(good)))
		save(); assert good, record['commands'][-1]
		return result.stdout

	def product(path):
		record['products'][str(path)] = dict(sha256=sha(path), bytes=path.stat().st_size); save()

	ccs = [cc for cc in ['gcc', 'clang-22'] if shutil.which(cc)]
	if not any('clang' in cc for cc in ccs) and shutil.which('clang'):
		ccs.append('clang')
	assert len(ccs) == 2, 'independent GCC and Clang required'
	assert shutil.which('valgrind'), 'unsuppressed memory qualification requires installed Valgrind'
	for fixture in ['basic', 'wide']:
		source = HERE / ('closure-' + fixture + '.astra')
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
			ir = run([compiler, '--dump-' + stage, source], stdout=None)
			(out / (fixture + '-' + stage + '.txt')).write_bytes(ir)
			if stage == 'llvm':
				assert re.search(rb'call fastcc (?:i32|i64) %', ir), 'closure invocation did not load transported code'
				assert b'closure.carrier' in ir and b'closure.environment.free' in ir, 'closure carrier or environment cleanup missing'
		for level in [0, 1, 2]:
			binary = out / f'closure-{fixture}-O{level}'
			run([compiler, f'-O{level}', source, '-o', binary]); run([binary]); product(binary)
			if level in [0, 2]: run([*VG, binary], memory=True)
	for name, (declarations, body, diagnostic) in NEGATIVES.items():
		source = out / ('negative-' + name + '.astra')
		source.write_text(declarations + '\nint main(){' + body + '}\n')
		extras = [ROOT / 'lib/astra/base/errors.astra'] if name == 'checked-code' else []
		run([compiler, '--check', source, *extras], code=1, diagnostic=diagnostic)
	for level in [0, 1, 2]:
		obj = out / f'closure-export-O{level}.o'
		run([compiler, f'-O{level}', '-c', HERE / 'closure-export.astra', '-o', obj]); product(obj)
		for cc in ccs:
			binary = out / f'{cc}-closure-client-O{level}'
			run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', HERE / 'closure-client.c', obj, '-o', binary])
			run([binary], stdout=b'closure-sum=21300 destroyed=200\n'); product(binary)
			if level in [0, 2]: run([*VG, binary], stdout=b'closure-sum=21300 destroyed=200\n', memory=True)
	providers = []
	for name in ['args', 'text', 'text-ops']:
		source = ROOT / f'lib/astra/platform/{name}-posix.c'; obj = out / (name + '-posix.o')
		run([ccs[0], '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', source, '-o', obj]); providers.append(obj)
	observer = out / 'closure-observer.o'
	run([ccs[0], '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE / 'closure-observer.c', '-o', observer])
	links = [part for obj in [observer, *providers] for part in ['--link-object', obj]]
	for name, app_id, cases, expected in [
		('owning-message-transform', 'A29', [(0, 0), (3, 0), (6, 1)], a29_trace),
		('checked-closure-rollback', 'A30', [(0,), (1,), (2,)], a30_trace)]:
		source = APPS / (name + '.astra')
		for level in [0, 1, 2]:
			binary = out / f'{name}-O{level}'
			run([compiler, f'-O{level}', source, *LIBS, *links, '-o', binary]); product(binary)
			for args in cases:
				trace = expected(*args); run([binary, *args], stdout=trace)
				if level in [0, 2]: run([*VG, binary, *args], stdout=trace, memory=True)
		record['applications'][app_id] = dict(source=str(source.relative_to(ROOT)), cases=[list(args) for args in cases], public_levels=[0, 1, 2], cleanup='Exact deterministic independent C event trace plus unsuppressed zero-leak Valgrind')
		record['source_sha256'][str(source.relative_to(ROOT))] = sha(source)
	for source in [*HERE.glob('closure-*'), *LIBS]:
		if source.is_file(): record['source_sha256'][str(source.relative_to(ROOT))] = sha(source)
	record['status'] = 'PASS'; save()
	print(f'PASS closures: {len(record["commands"])} checks; {len(record["products"])} products; A29/A30; exact C cleanup witnesses; GCC/Clang; unsuppressed Valgrind')


if __name__ == '__main__':
	main(*sys.argv[1:])
