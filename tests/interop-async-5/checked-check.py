#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Checked native indirect calls: public artifacts, effects and exact cleanup."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ERROR = '[ExceptionRoot] class Error{init(){}virtual property string message{get{return "error";}}} class Other:Error{init():base(){}} '
ENV = 'class Env{init(){}} '
CODE = 'int code(borrowed Env env,int x)throws Error{if(x<0){throw new Error();}return x;} '
BIND = 'var env=new Env();var f=checked_closure_bind(move env,code);'
NEGATIVES = {
	'unhandled-effect': (ENV + CODE, BIND + 'return closure_invoke(f,1);', 'checked exception'),
	'nonthrow-bind': (ENV + 'int code(borrowed Env env,int x){return x;}', BIND + 'return 0;', 'checked closure code requires an exact throwing native function'),
	'ordinary-alias': (ENV + CODE, BIND + 'owned Closure<Env,int,int> g=move f;return 0;', 'expected initializer'),
	'error-bound-alias': (ENV + CODE, BIND + 'owned CheckedClosure<Env,Other,int,int> g=move f;return 0;', 'expected initializer'),
	'bad-error-type': (ENV + CODE, 'CheckedClosure<Env,Env,int,int> f=null;return 0;', 'exception type must derive'),
	'bad-result-type': (ENV + CODE, 'CheckedClosure<Env,Error,string,int> f=null;return 0;', 'copied scalar signature'),
	'wrong-argument': (ENV + CODE, BIND + 'try{return closure_invoke(f,true);}catch(Error e){return 0;}', 'exact scalar signature type'),
	'wrong-arity': (ENV + CODE, BIND + 'try{return closure_invoke(f);}catch(Error e){return 0;}', 'exact arity'),
	'call-after-release': (ENV + CODE, BIND + 'release f;try{return closure_invoke(f,1);}catch(Error e){return 0;}', 'released owned value'),
	'double-capture': (ENV + CODE, BIND + 'var g=checked_closure_bind(move env,code);return 0;', 'moved owned value'),
	'wrong-environment': (ENV + 'class Different{init(){}}int code(borrowed Different env,int x)throws Error{return x;}', BIND + 'return 0;', 'checked closure code requires an exact throwing native function'),
	'effect-narrowing': (ENV + CODE + 'int call(borrowed CheckedClosure<Env,Error,int,int> f)throws Other{return closure_invoke(f,1);}', 'return 0;', 'checked exception'),
	'wrong-catch': (ENV + CODE, BIND + 'try{return closure_invoke(f,1);}catch(Other e){return 0;}', 'checked exception'),
	'bare-fn-alias': ('int checked(int x)throws Error{return x;}', 'Fn<int,int> f=checked;return 0;', 'nonthrowing'),
	'consume-invoking-closure': (ENV + CODE + 'int take(owned CheckedClosure<Env,Error,int,int> f){return 1;}', BIND + 'try{return closure_invoke(f,take(move f));}catch(Error e){return 0;}', 'forbids moving its backing'),
	'consume-shared-loan-backing': (ENV + 'int take(borrowed Env env,owned Shared<Env> owner){return 1;}', 'var payload=new Env();var state=shared_acquire(move payload);return take(shared_borrow(state),move state);', 'forbids moving its backing'),
}
VG = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99']
EXPECTED = ('checked=1:10\n' + 'checked=1:20\nchecked=2:20\n' * 3 + 'checked=4:1\n' + 'checked=1:20\nchecked=2:20\n' * 2 + 'checked=3:40\nchecked=2:10\nchecked=4:2\n').encode()

def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main(compiler, output):
	compiler = Path(compiler).resolve(); out = Path(output).resolve()
	assert not out.is_relative_to(ROOT)
	out.mkdir(parents=True, exist_ok=True)
	record = dict(compiler=dict(path=str(compiler), sha256=sha(compiler)), commands=[], products={}, source_sha256={}, scope='Exact checked native heap-Class closure, precise Error bound, scalar signature; no exception across C')
	def save():
		(out / 'results.json').write_text(json.dumps(record, indent=2) + '\n')
	def run(argv, code=0, stdout=b'', diagnostic=None, memory=False):
		argv = list(map(str, argv)); start = time.monotonic()
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=180, env=dict(os.environ, CCACHE_DISABLE='1'))
		good = result.returncode == code and (stdout is None or result.stdout == stdout)
		if diagnostic:
			good &= diagnostic.encode() in result.stderr and re.search(rb':[0-9]+:[0-9]+: error:', result.stderr) is not None and b'internal error' not in result.stderr.lower()
		elif memory:
			good &= all(x in result.stderr for x in [b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			good &= not result.stderr
		record['commands'].append(dict(argv=argv, exit=result.returncode, expected_exit=code, stdout_hex=result.stdout.hex(), stderr_hex=result.stderr.hex(), expected_stdout_hex=None if stdout is None else stdout.hex(), diagnostic=diagnostic, memory=memory, seconds=time.monotonic()-start, passed=bool(good)))
		save(); assert good, record['commands'][-1]
		return result.stdout
	cc = shutil.which('gcc'); assert cc and shutil.which('valgrind')
	observer = out / 'checked-observer.o'
	run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE / 'checked-observer.c', '-o', observer])
	for fixture in ['basic', 'wide', 'loop', 'borrow-owned']:
		source = HERE / ('checked-' + fixture + '.astra')
		for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']:
			ir = run([compiler, '--dump-' + stage, source], stdout=None)
			(out / (fixture + '-' + stage + '.txt')).write_bytes(ir)
			if stage == 'llvm':
				assert re.search(rb'call fastcc ptr %', ir), 'missing actual checked indirect physical call'
				assert b'closure.success' in ir and b'closure.invoke.result' in ir
			if stage == 'ssa':
				assert b'checked-invoke-closure' in ir and b'checked-closure-success' in ir
		for level in [0, 1, 2]:
			binary = out / f'checked-{fixture}-O{level}'
			links = ['--link-object', observer] if fixture == 'basic' else []
			run([compiler, f'-O{level}', source, *links, '-o', binary])
			expected = EXPECTED if fixture == 'basic' else b''
			run([binary], stdout=expected)
			record['products'][str(binary)] = dict(sha256=sha(binary), bytes=binary.stat().st_size)
			if level in [0, 2]: run([*VG, binary], stdout=expected, memory=True)
	for name, (declarations, body, diagnostic) in NEGATIVES.items():
		source = out / ('negative-' + name + '.astra')
		source.write_text(ERROR + declarations + '\nint main(){' + body + '}\n')
		run([compiler, '--check', source], code=1, diagnostic=diagnostic)
	for source in HERE.glob('checked-*'):
		if source.is_file(): record['source_sha256'][str(source.relative_to(ROOT))] = sha(source)
	record['status'] = 'PASS'; save()
	print(f'PASS checked closures: {len(record["commands"])} public command checks; twelve O0/O1/O2 artifacts; precise cleanup and unsuppressed Valgrind')

if __name__ == '__main__':
	main(*sys.argv[1:])
