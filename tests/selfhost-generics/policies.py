#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""C0-admitted unported policies and semantic conflicts must never emit."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

CASES = {
	'recursive-instance': (['T recur<T>(T x) { return recur<T>(x); } int main() { return recur<int>(1); }'], 0),
	'virtual-method': (['class Echo<T> { init() {} virtual T echo(T value) { return value; } } int main() { var e=new Echo<int>(); return e.echo(1)-1; }'], 0),
	'generic-buffer-field': (['struct Box<T> { T[] value; } int main() { Box<int> a={value=new int[2]}; return 0; }'], 1),
	'generic-record-buffer-copy': (['struct Box<T> { T[] value; } int main() { Box<int> a={value=new int[2]}; var b=a; return 0; }'], 1),
	'foreign-generic': (['extern(C) T external<T>(T x); int main() { return external<int>(1); }'], 1),
	'cross-unit-conflict': (['T identity<T>(T x) { return x; }', 'T identity<T>(T x) { return x; } int main() { return identity<int>(1); }'], 1),
	'unapproved-Class-transfer-ABI': (['class Echo<T>{init(){} T echo(T value){return value;}} owned Echo<int> relay(owned Echo<int> value){return move value;} int main(){var a=new Echo<int>();var b=relay(move a);return b.echo(43)-43;}'], 0),
}


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'component', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	rows, commands = [], []
	def run(argv, name):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], capture_output=True, cwd=a.build, timeout=180)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	for name, (texts, c0_exit) in CASES.items():
		sources = []
		for i, text in enumerate(texts):
			path = a.runtime/(name+'-'+str(i)+'.astra'); path.write_text(text+'\n'); sources.append(path)
		parsed = run([a.compiler, '--parse', *sources], name+'-parse')
		assert parsed.returncode == (1 if name == 'foreign-generic' else 0), (name, parsed.stderr)
		if name == 'foreign-generic': assert b'generic extern(C)' in parsed.stderr
		c0 = run([a.compiler, '--check', *sources], name+'-C0'); assert c0.returncode == c0_exit, (name, c0.returncode, c0.stderr)
		admit = run([a.component, '--nativeabi-admit', a.mode, a.build/'unused', *sources], name+'-admit')
		abi_only = name == 'unapproved-Class-transfer-ABI'
		if abi_only:
			assert admit.returncode == 0 and b'STATUS 0 0' in admit.stdout
		else:
			assert admit.returncode in (1, 3) and (b'CHECKED_ERROR' in admit.stdout or b'DEFER ' in admit.stdout), (name, admit.returncode, admit.stdout, admit.stderr)
		diagnostics = [bytes.fromhex(line.split()[-1]) for line in admit.stdout.decode().splitlines() if line.startswith('CHECKED_ERROR ')]
		if c0_exit == 0 and not abi_only:
			assert any(b'DEFERRED' in text for text in diagnostics) or b'DEFER ' in admit.stdout, (name, admit.stdout)
		out = a.build/(name+'.o'); out.write_bytes(b'refused-policy-sentinel\n'); before = sha(out)
		emit = run([a.component, '--emit-obj', a.mode, out, *sources], name+'-emit')
		assert emit.returncode == 2 and sha(out) == before
		if abi_only: assert b'LLVM_DEFERRED: Class ABI is qualified only for the hidden borrowed receiver' in emit.stderr
		rows.append(dict(name=name, sources=[dict(path=str(path), sha256=sha(path)) for path in sources], independent_c0_parse_exit=parsed.returncode, independent_c0_exit=c0.returncode, independent_c0_diagnostic=c0.stderr.decode(), native_exit=admit.returncode, native_diagnostic=admit.stdout.decode(), checked_diagnostics=[text.decode() for text in diagnostics], destination_preserved=before, classification='REJECTED' if name == 'cross-unit-conflict' else 'DEFERRED', limitation='Generic field cases fail the C0 storage premise before any copy; foreign generic ABI is refused at the C0 parser policy.' if name.startswith(('generic-', 'foreign-')) else '', result='PASS'))
		(a.runtime/'results.json').write_text(json.dumps(rows, indent=2)+'\n')
		print(name, a.mode, rows[-1]['classification'], flush=True)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, cases=rows), indent=2)+'\n')


if __name__ == '__main__':
	main()
