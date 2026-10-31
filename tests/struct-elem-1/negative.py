# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Retain exact diagnostics for excluded composition and live backing addresses."""
from pathlib import Path
import json
import subprocess
import sys

PRELUDE = '''struct S { int x; void scale(int n) { this.x = this.x * n; } }
struct O { S inner; }
int take(owned S[] a) { return 1; }
S produce(owned S[] a) { S v = {x = 1}; return v; }
void borrow_and_take(S[] a, owned S[] b) {}
class C { owned O[] records; init() { this.records = new O[2]; } int replace() { this.records = new O[3]; return 1; } }
'''
CASES = {
	'missing-entry': ('int f(){S[2] a={{x=1}};return 0;}', 'exactly 2'),
	'extra-entry': ('int f(){S[1] a={{x=1},{x=2}};return 0;}', 'exactly 1'),
	'missing-field': ('int f(){S[1] a={{}};return 0;}', 'missing'),
	'duplicate-field': ('int f(){S[1] a={{x=1,x=2}};return 0;}', 'duplicate'),
	'unknown-field': ('int f(){S[1] a={{z=1}};return 0;}', "unknown initializer field 'z'"),
	'own-initializer': ('int f(){S[1] a={a[0]};return 0;}', 'unknown'),
	'structural-conversion': ('struct T{int x;}int f(){T t={x=1};S[1] a={t};return 0;}', 'exact nominal'),
	'phantom-identity': ('struct P<T>{int x;}void f(){var a=new P<int>[1];var b=new P<f32>[1];a[0]=b[0];}', 'exact nominal'),
	'signed-identity': ('struct Box<T>{T value;}void f(){var a=new Box<int>[1];var b=new Box<u32>[1];a[0]=b[0];}', 'exact nominal'),
	'generic-function-buffer': ('T identity<T>(T a){return a;}void f(){var a=new S[1];var b=identity(a);}', 'GEN1_PLAIN_COPY'),
	'parameterized-elements': ('void f<T>(int n){var a=new T[n];}', 'element'),
	'array-copy': ('void f(){S[1] a={{x=1}};S[1] b=a;}', 'initializer'),
	'array-parameter': ('void f(S[1] a){}', 'array parameter'),
	'array-result': ('S[1] f(){S[1] a={{x=1}};return a;}', 'array result'),
	'array-field': ('struct A{S[1] a;}', 'array struct fields'),
	'array-decay': ('void use(S[] a){}void f(){S[1] a={{x=1}};use(a);}', 'whole-array'),
	'view-subslice': ('void f(S[] a){var b=slice(a,0,1);}', 'array'),
	'view-escape': ('S[] f(){S[1] a={{x=1}};return slice(a);}', 'slice'),
	'owner-persistent-alias': ('void f(){var a=new S[1];S[] b=a;}', 'borrow'),
	'owner-copy': ('void f(){var a=new S[1];owned S[] b=a;}', 'move'),
	'element-address': ('void f(){var a=new S[1];S* p=&a[0];}', 'address'),
	'subfield-address': ('void f(){var a=new S[1];int* p=&a[0].x;}', 'address'),
	'leaf-member': ('void f(){var a=new S[1];a[0].x.value=1;}', 'StructType'),
	'vector-member': ('struct V{f32<4> v;}void f(){var a=new V[1];a[0].v.x=1.0f;}', 'StructType'),
	'vector-lane-place': ('struct V{f32<4> v;}void f(){var a=new V[1];a[0].v[0]=1.0f;}', "expected '='"),
	'readonly-copy-param': ('void f(S a){a.x=2;}', 'read-only'),
	'readonly-copy-receiver': ('void f(S a){a.scale(2);}', 'read-only'),
	'borrow-and-move': ('void f(){var a=new S[1];borrow_and_take(a,move a);}', 'borrow'),
	'read-after-move': ('void f(){var a=new S[1];take(move a);var b=a[0];}', 'moved'),
	'destination-move': ('void f(){var a=new S[1];a[0]=produce(move a);}', 'moved'),
	'field-destination-move': ('void f(){var a=new S[1];a[0].x=take(move a);}', 'moved'),
	'receiver-move': ('void f(){var a=new S[1];a[0].scale(take(move a));}', 'moved'),
	'index-move': ('void f(){var a=new S[1];var b=a[take(move a)];}', 'moved'),
	'object-field-replacement': ('void f(C c){c.records[0].inner.x=c.replace();}', 'overlap'),
	'object-alias-replacement': ('void f(C c){C b=c;c.records[0].inner.x=b.replace();}', 'overlap'),
	'ordinary-nested-receiver': ('void f(){O o={inner={x=1}};o.inner.scale(2);}', 'method invocation on a nested struct subobject'),
	'object-receiver-replacement': ('void f(C c){c.records[0].inner.scale(c.replace());}', 'overlap'),
	'object-copy-replacement': ('O change(C c){c.replace();O x={inner={x=1}};return x;}void f(C c){c.records[0]=change(c);}', 'overlap'),
	'object-later-argument': ('void pair(O[] a,int x){}void f(C c){pair(c.records,c.replace());}', 'overlap'),
	'object-field-release': ('void f(C c){release c.records;}', 'owned field'),
	'object-field-move': ('void f(C c){owned O[] a=move c.records;}', 'moving ownership out'),
	'object-index-replacement': ('void f(C c){var b=c.records[c.replace()];}', 'overlap'),
	'count-u32': ('void f(u32 n){var a=new S[n];}', 'int/i32'),
	'bound-zero': ('void f(){S[0] a={{x=1}};}', '1..1024'),
	'bound-large': ('void f(){S[1025] a={{x=1}};}', '1..1024'),
	'empty-struct': ('struct Empty{}void f(){var a=new Empty[1];}', 'empty'),
	'layout-cycle': ('struct Cycle{Cycle field;}void f(){var a=new Cycle[1];}', 'recursive'),
	'text-field': ('struct Bad{string field;}void f(){var a=new Bad[1];}', 'field'),
	'typed-pointer-field': ('struct Bad{int* field;}void f(){var a=new Bad[1];}', 'field'),
	'slice-field': ('struct Bad{S[] field;}void f(){var a=new Bad[1];}', 'field'),
	'class-field': ('struct Bad{C field;}void f(){var a=new Bad[1];}', 'field'),
	'foreign-slice': ('extern(C) void use(S[] a);', 'C'),
	'foreign-record': ('extern(C) void use(S a);', 'C'),
	'foreign-pointer': ('extern(C) void use(S* a);', 'C'),
}

# GEN-COPY-1 and the approved M15 producer projection admit these exact inputs.
SUPERSEDED = {
	'generic-function-record': ('T identity<T>(T a){return a;}void f(){var a=new S[1];var b=identity(a[0]);}', None),
	'temporary-member': ('S make(){S a={x=1};return a;}int f(){return make().x;}', None),
}


def main(compiler, output):
	output.mkdir(parents=True, exist_ok=False)
	results = []
	for name, (body, expected) in (CASES | SUPERSEDED).items():
		path = output/(name+'.astra')
		path.write_text(PRELUDE+body+'\n')
		for stage in ['cfg', 'ssa', 'nabi', 'llvm']:
			result = subprocess.run([compiler, '--dump-'+stage, path.name], cwd=output, capture_output=True, text=True)
			(output/(name+'.'+stage+'.stderr')).write_text(result.stderr)
			results.append(dict(name=name, stage=stage, status=result.returncode, diagnostic=result.stderr, expected=expected))
			if expected is None:
				assert result.returncode == 0 and not result.stderr, results[-1]
				(output/(name+'.'+stage)).write_text(result.stdout)
				continue
			if result.returncode != 1 or result.stdout or expected.lower() not in result.stderr.lower():
				(output/'preliminary-results.json').write_text(json.dumps(results, indent='\t')+'\n')
				raise AssertionError(results[-1])
	(output/'results.json').write_text(json.dumps(results, indent='\t')+'\n')
	print(f'{len(results)} retained exclusion checks')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
