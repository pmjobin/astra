#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Parser-valid C0 semantic negatives; no rejected/deferred source may emit."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
CASES = {
	'arity': ('T id<T>(T x) { return x; } int main() { return id<int,bool>(1); }', 'argument'),
	'inferred-conflict': ('T same<T>(T x,T y) { return x; } int main() { return same(1,true); }', 'type'),
	'explicit-conflict': ('T id<T>(T x) { return x; } int main() { return id<int>(true); }', 'type'),
	'constraint': ('T add<T>(T x,T y) where T : Numeric { return x+y; } int main() { var b=add<bool>(true,false); return 0; }', 'capability'),
	'nominal': ('struct A<T> { T value; } struct B<T> { T value; } int take(A<int> x) { return x.value; } int main() { B<int> b={value=1}; return take(b); }', 'type'),
	'instance-reuse': ('struct Box<T> { T value; } int take(Box<int> x) { return x.value; } int main() { Box<bool> b={value=true}; return take(b); }', 'type'),
	'argument-order': ('B second<A,B>(A a,B b) { return b; } int main() { return second<int,bool>(true,1); }', 'type'),
	'record-arity': ('struct Box<T> { T value; } int main() { Box<int,bool> b={value=1}; return 0; }', 'argument'),
	'move-after-use': ('owned T[] relay<T>(owned T[] x) { return move x; } int main() { var a=new int[3]; var b=relay<int>(move a); return len(a); }', 'moved'),
	'duplicate-owner': ('owned T[] relay<T>(owned T[] x) { owned T[] y=x; return move y; } int main() { var a=new int[3]; var b=relay<int>(move a); return 0; }', 'move'),
	'borrow-consume': ('int inspect<T>(T[] x,owned T[] y) { return len(x); } int main() { var a=new int[3]; return inspect<int>(a,move a); }', 'borrow'),
	'borrow-escape': ('T[] escape<T>(T[] x) { return x; } int main() { var a=new int[3]; var b=escape<int>(a); return len(b); }', 'borrow'),
	'wrong-receiver': ('class A<T> { init() {} T echo(T value) { return value; } } class B<T> { init() {} } int main() { var b=new B<int>(); return b.echo(1); }', 'method'),
}


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('component', 'compiler', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	commands, results = [], []
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(list(map(str, argv)), capture_output=True, timeout=90, cwd=a.build)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, argv)), name=name, exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	for name, (text, diagnostic) in CASES.items():
		source = a.runtime/(name+'.astra'); source.write_text(text+'\n')
		parsed = run([a.compiler, '--parse', source], name+'-parse'); assert parsed.returncode == 0, (name, parsed.stderr)
		oracle = run([a.compiler, '--check', source], name+'-C0'); assert oracle.returncode == 1 and diagnostic.encode() in oracle.stderr.lower(), (name, oracle.stderr)
		admission = run([a.component, '--nativeabi-admit', a.mode, a.build/'unused', source], name+'-native')
		assert admission.returncode in (1, 3), (name, admission.returncode, admission.stderr)
		assert b'CHECKED_ERROR' in admission.stdout or b'ERROR ' in admission.stdout or b'DEFER ' in admission.stdout
		out = a.build/(name+'.o'); out.write_bytes(b'unchanged-rejected-destination\n'); before = sha(out)
		emit = run([a.component, '--emit-obj', a.mode, out, source], name+'-refuse-object')
		assert emit.returncode == 2 and sha(out) == before, (name, emit.returncode, emit.stderr)
		results.append(dict(name=name, source_path=str(source), source_sha256=sha(source), c0_diagnostic=oracle.stderr.decode(), native_exit=admission.returncode, native_stdout_sha256=hashlib.sha256(admission.stdout).hexdigest(), destination_preserved=before, result='PASS'))
		(a.runtime/'results.json').write_text(json.dumps(results, indent=2)+'\n')
		print(name, a.mode, 'rejected/deferred; destination preserved', flush=True)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, cases=results), indent=2)+'\n')


if __name__ == '__main__':
	main()
