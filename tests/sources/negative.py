# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Deterministic diagnostics, exact per-file positions, and CLI path policy."""
from pathlib import Path
import itertools
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CASES = {
	'duplicate-function': (['int helper(){return 1;}', '\nint helper(){return 2;}'], 'b.astra:2:5:', "duplicate function 'helper'"),
	'duplicate-main': (['int main(){return 1;}', 'int main(){return 2;}'], 'b.astra:1:5:', "duplicate function 'main'"),
	'duplicate-struct': (['struct S{int x;}', 'struct S{int y;}'], 'b.astra:1:8:', "duplicate struct type 'S'"),
	'duplicate-class': (['class C{}', 'class C{}'], 'b.astra:1:7:', "duplicate class type 'C'"),
	'duplicate-generic': (['struct Box<T>{T value;}', 'struct Box<T>{T value;}'], 'b.astra:1:8:', "duplicate or conflicting generic struct type 'Box'"),
	'syntax': (['int helper(){return 1;}', '\nint broken(){\n\treturn @;\n}'], 'b.astra:3:9:', 'unexpected character'),
	'independent-parse': (['int helper(', 'int x){return x;}'], 'a.astra:2:1:', 'expected'),
	'semantic': (['int helper(int x){return x;}', '\nint main(){return helper(true);}'], 'b.astra:2:', 'argument'),
	'nominality': (['struct A{int x;} int take(A a){return a.x;}', 'struct B{int x;} int main(){B b={x=1};return take(b);}'], 'b.astra:1:', 'equal layout is insufficient'),
	'ownership': (['void consume(owned R r){} int inspect(R r){return id(r);}', '\nint main(){var r=resource(1);consume(move r);return inspect(r);}'], 'b.astra:2:', 'moved'),
	'owned-bare': (['void consume(owned R r){}', 'int main(){var r=resource(1);consume(r);return 0;}'], 'b.astra:1:', 'move'),
	'class-overlap': (['class C{int x;init(){this.x=0;}} void both(C a,owned C b){}', 'int main(){var c=C.init();both(c,move c);return 0;}'], 'b.astra:1:', 'borrow'),
	'generic-use': (['T identity<T>(T x){return x;}', '\nint main(){return identity<int,bool>(1);}'], 'b.astra:2:', 'type argument'),
	'generic-definition': (['T wrong<T>(T x){return missing(x);}', 'int main(){return wrong<int>(1);}'], 'a.astra:1:', 'unknown function'),
	'struct-cycle': (['struct A{B b;}', 'struct B{A a;}'], 'a.astra:1:8:', 'recursive by-value struct layout'),
	'generic-cycle': (['struct A<T>{B<T> b;}', 'struct B<T>{A<T> a;}', 'void use(A<int>* a){}'], 'astrac:', 'recursive generic struct layout: A<int> → B<int> → A<int>'),
	'error-selection': (['int alpha(){return absent_a();}', 'int beta(){return absent_b();}'], 'a.astra:1:', "unknown function 'absent_a'"),
}


def invoke(compiler, args, cwd):
	return subprocess.run([str(compiler), *map(str, args)], cwd=cwd, capture_output=True, text=True)


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True); records = []
	for name, (texts, location, message) in CASES.items():
		directory = out/name; directory.mkdir(exist_ok=True)
		paths = [chr(ord('a')+i)+'.astra' for i in range(len(texts))]
		for path, text in zip(paths, texts):
			(directory/path).write_text(text+'\n')
		expected = None
		for order in itertools.permutations(paths):
			for stage in ['--check', '--dump-llvm']:
				p = invoke(compiler, [stage, *order, '--vapi', ROOT/'tests/param-borrow/fixtures/runtime.vapi'], directory)
				assert p.returncode == 1 and not p.stdout and p.stderr.startswith(location) and message in p.stderr, (name, p.returncode, p.stdout, p.stderr, location, message)
				if name.startswith('duplicate'):
					assert 'previous declaration: a.astra:1:' in p.stderr, (name, p.stderr)
				if expected is None:
					expected = p.stderr; (directory/'diagnostic.txt').write_text(expected)
				assert p.stderr == expected, (name, order)
				records.append(dict(name=name, order=order, stage=stage, diagnostic=p.stderr))
				# CLI behavior uses relative names even though this test's output is temporary.
	for order in [('duplicate-a.astra', 'duplicate-b.astra'), ('duplicate-b.astra', 'duplicate-a.astra')]:
		p = invoke(compiler, ['--check', *order], ROOT/'tests/sources/fixtures/invalid')
		assert p.returncode == 1 and not p.stdout and p.stderr == (ROOT/'tests/sources/goldens/duplicate.stderr').read_text(), p
	(out/'foo.astra').write_text('int main(){return 0;}\n'); (out/'sub').mkdir(exist_ok=True)
	(out/'sub/bar.astra').write_text('int helper(){return 1;}\n')
	checks = [([], 2, 'no action specified'), (['--parse'], 2, 'expected exactly one file'), (['foo.astra','./foo.astra'], 2, "source file 'foo.astra' was supplied more than once"), (['sub//./bar.astra','sub/bar.astra'], 2, "source file 'sub/bar.astra' was supplied more than once"), (['--check','foo.astra','missing.astra'], 1, 'missing.astra: error: cannot read source file')]
	for args, code, message in checks:
		p = invoke(compiler, args, out); assert p.returncode == code and not p.stdout and message in p.stderr, (args, p)
		records.append(dict(name='cli', args=args, diagnostic=p.stderr))
	for mode in ['--parse', '--check', '--dump-syntax']:
		p = invoke(compiler, [mode, './foo.astra', 'sub//./bar.astra'], out); assert p.returncode == 0 and not p.stderr, p
		if mode == '--dump-syntax':
			assert '(source "foo.astra"' in p.stdout and '(source "sub/bar.astra"' in p.stdout and str(out) not in p.stdout
			# The baseline accepts arbitrary filename suffixes; preserve that policy.
	(out/'input.txt').write_text('int other(){return 0;}\n')
	assert invoke(compiler, ['--check','input.txt'], out).returncode == 0
	# Same basename, distinct directory, plus global entry in a third unit.
	p = invoke(compiler, ['--check', 'a/common.astra', 'b/common.astra', 'main.astra'], ROOT/'tests/sources/fixtures'); assert p.returncode == 0 and not p.stderr, p
	# Paths are escaped in the source-set dump, never interpolated into a shell.
	(out/'a "quote".astra').write_text('int quoted(){return 0;}\n')
	p = invoke(compiler, ['--dump-syntax','foo.astra','a "quote".astra'], out); assert p.returncode == 0 and '(source "a \\"quote\\".astra"' in p.stdout, p.stdout
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n'); print(f'{len(records)} deterministic diagnostic checks')


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
