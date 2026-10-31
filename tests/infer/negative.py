# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Targetless typing, ownership, lifetime and reserved-keyword rejection matrix."""
# Approved declaration/inference promotions retain exact originals and
# O0/O1/O2 memory-tested counterparts in structural-generics-15/historical-observations.
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PARSER = {
	'baseline-identifier-probe': ('int main() {\n\tint var = 1;\n\tvar = var + 1;\n\treturn var;\n}', "'var' is a reserved keyword for inferred local declarations"),
	'baseline-type-probe': ('struct var { int value; }\nvar make() {\n\tvar result = { value = 1 };\n\treturn result;\n}\nint main() {\n\tvar result = make();\n\treturn result.value;\n}', "'var' is a reserved keyword for inferred local declarations"),
	'no-initializer': ('void f(){var x;}', 'inferred local declaration requires an initializer'),
	'empty-initializer': ('void f(){var x=;}', 'inferred local declaration requires an initializer'),
	'explicit-prefix': ('void f(){var int x=1;}', 'cannot include an explicit type'),
	'explicit-colon': ('void f(){var x:int=1;}', 'cannot include an explicit type'),
	'empty-aggregate': ('void f(){var x={};}', 'cannot infer local type'),
	'positional-aggregate': ('void f(){var x={1,2};}', 'cannot infer local type'),
	'named-aggregate': ('void f(){var x={value=1};}', 'cannot infer local type'),
	'no-colon-equals': ('void f(){x:=1;}', "unexpected character ':'"),
}
for name, source in {
	'old-local': 'void f(){int var=1;}',
	'old-assignment': 'void f(){var=var+1;}',
	'old-struct': 'struct var{int value;}',
	'old-class': 'class var{}',
	'old-function': 'int var(){return 1;}',
	'old-field': 'struct S{int var;}',
	'old-parameter': 'void f(int var){}',
	'old-reference': 'int f(){return var;}',
	'old-type-parameter': 'T f<var>(T x){return x;}',
	'old-property': 'class C{property int var{get{return 1;}}}',
	'parameter': 'void f(var x){}',
	'result': 'var f(){return 1;}',
	'struct-field': 'struct S{var x;}',
	'class-field': 'class C{var x;}',
	'property': 'class C{property var x{get{return 1;}}}',
	'foreign-result': 'extern(C) var f();',
	'foreign-name': 'extern(C) int var();',
}.items():
	PARSER['reserved-'+name] = (source, "'var' is a reserved keyword for inferred local declarations")

SEMANTIC = {
	'receiver-value': ('struct S{int x;void f(){var self=this;}}', "only 'this.field' and 'this.method(...)' are supported"),
	'self': ('void f(){var x=x;}', "unknown name 'x'"),
	'mutual': ('void f(){var x=y;var y=x;}', "unknown name 'y'"),
	'duplicate': ('void f(){var x=1;var x=2;}', "duplicate local 'x'"),
	'shadow': ('void f(){var x=1;{var x=2;}}', "duplicate local 'x'"),
	'parameter-shadow': ('void f(int x){var x=1;}', "conflicts with parameter"),
	'reassign': ('void f(){var x=1;x=2.0f;}', "expected assignment value of type 'int'"),
	'later-argument': ('void use(f64 x){}void f(){var x=1.0;use(x);}', "expects type 'f64'"),
	'void': ('void empty(){}void f(){var x=empty();}', 'cannot be used as a value'),
	'array-copy': ('void f(){int[2] a={1,2};var x=a;}', 'whole-array values'),
	'unresolved-struct': ('struct S<T>{T x;}struct B<T>{T x;}void f<T>(T x){S<T> a={x=x};var b=a;B<T> c=b;}', 'exact nominal type'),
	'generic-phantom-needs-arguments': ('int marker<T>(int x){return x;}void f(){var y=marker(1);}', "cannot infer generic type argument 'T'"),
	'overloads': ('int f(int x){return x;}f64 f(f64 x){return x;}void g(){var x=f(1);}', "duplicate function"),
	'nominal': ('struct A{int x;}struct B{int x;}void f(){A a={x=1};var inferred=a;B b=inferred;}', 'exact nominal type'),
	'generic-nominal': ('struct A<T>{T x;}struct B<T>{T x;}void f(){A<int> a={x=1};var inferred=a;B<int> b=inferred;}', 'exact nominal type'),
	'buffer-copy': ('void f(){var a=new f64[3];var b=a;}', 'owned buffer cannot be copied'),
	'buffer-parenthesized-copy': ('void f(){var a=new f64[3];var b=(a);}', 'owned buffer cannot be copied'),
	'buffer-persistent-slice': ('void f(){var a=new f64[3];var b=slice(a,0,3);}', 'slice source must be a direct fixed-array local'),
	'resource-copy': ('void f(){var a=resource(1);var b=a;}', "owned local 'a' cannot be copied"),
	'resource-parenthesized-copy': ('void f(){var a=resource(1);var b=(a);}', "owned local 'a' cannot be copied"),
	'object-copy': ('class C{init(){}}void f(){var a=C.init();var b=a;}', 'persistent alias'),
	'object-move-deferred': ('class C{init(){}}void f(){var a=C.init();var b=move a;}', 'local owner moves are unsupported'),
	'constructor-parenthesized': ('class C{init(){}}void f(){var a=(C.init());}', 'fresh class local initializer'),
	'constructor-subexpression': ('class C{init(){}}void f(){var a=C.init()==null;}', 'fresh class local initializer'),
	'borrowed-raw-local': ('void f(borrowed void* p){var alias=p;}', 'cannot be stored'),
	'borrowed-resource-local': ('void f(borrowed R p){var alias=p;}', 'cannot be stored'),
	'borrowed-escape': ('void f(){int a=1;var p=&a;{int b=2;var q=&b;p=q;}}', 'shorter lexical lifetime'),
	'slice-escape': ('void f(){int[2] a={1,2};var outer=slice(a,0,2);{int[2] b={3,4};var inner=slice(b,0,2);outer=inner;}}', 'shorter lexical lifetime'),
	'wrong-buffer-replacement': ('void f(){var a=new f64[3];a=new f32[3];}', 'exact owned buffer result'),
	'owned-field-alias': ('class C{owned R r;init(){this.r=resource(1);}void f(){var alias=this.r;}}', 'owned Resource field use'),
	'let': ('void f(){let x=1;}', "unknown type 'let'"),
	'final': ('void f(){final x=1;}', "unknown type 'final'"),
}
FLOW = {
	'buffer-after-move': ('void f(){var a=new f64[3];var b=move a;int n=len(a);}', 'moved'),
	'resource-after-move': ('void f(){var a=resource(1);var b=move a;int n=id(a);}', 'moved'),
	'object-after-move': ('class C{init(){}}void consume(owned C c){}void f(){var a=C.init();consume(move a);bool b=a==null;}', 'moved'),
	'buffer-after-release': ('void f(){var a=new f64[3];release a;int n=len(a);}', 'released'),
	'resource-after-release': ('void f(){var a=resource(1);release a;int n=id(a);}', 'released'),
	'branch-move': ('void f(bool yes){var a=new f64[3];if(yes){var b=move a;}int n=len(a);}', 'owned'),
}


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	# Parametric plain-copy record inference is admitted by the later generic
	# storage contract. Exercise it concretely while retaining nominal refusal.
	positive = out / 'parametric-record-current.astra'
	positive.write_text('struct S<T>{T x;}T f<T>(T x){S<T> a={x=x};var b=a;return b.x;}int main(){return f<int>(42);}' + '\n')
	positive_rows = []
	for stage in ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
		command = [str(compiler), '--dump-' + stage, str(positive)]
		p = subprocess.run(command, capture_output=True, text=True, timeout=30)
		positive_rows.append(dict(command=command, exit=p.returncode, stderr=p.stderr, passed=p.returncode == 0 and bool(p.stdout) and not p.stderr))
		assert positive_rows[-1]['passed'], positive_rows[-1]
	for level in [0, 2]:
		binary = out / ('parametric-record-current-O' + str(level))
		command = [str(compiler), '-O' + str(level), str(positive), '-o', str(binary)]
		p = subprocess.run(command, capture_output=True, text=True, timeout=30)
		positive_rows.append(dict(command=command, exit=p.returncode, stderr=p.stderr, passed=p.returncode == 0 and not p.stdout and not p.stderr))
		assert positive_rows[-1]['passed'], positive_rows[-1]
		p = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
		positive_rows.append(dict(command=[str(binary)], exit=p.returncode, passed=p.returncode == 42 and not p.stdout and not p.stderr))
		assert positive_rows[-1]['passed'], positive_rows[-1]
	(out / 'positive-results.json').write_text(json.dumps(positive_rows, indent='\t') + '\n')
	records = []
	failures = []
	for cases, stages in [(PARSER, ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']), (SEMANTIC, ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']), (FLOW, ['cfg', 'ssa', 'nabi', 'cabi', 'llvm'])]:
		for name, (source, expected) in cases.items():
			path = out/(name+'.astra'); path.write_text(source+'\n')
			for stage in stages:
				p = subprocess.run([str(compiler), '--dump-'+stage, str(path)] + ([] if stage == 'syntax' else ['--vapi', str(ROOT/'tests/infer/fixtures/runtime.vapi')]), capture_output=True, text=True)
				if p.returncode != 1 or p.stdout or expected not in p.stderr:
					failures.append((name, stage, expected, p.returncode, p.stdout, p.stderr))
				records.append(dict(name=name, stage=stage, diagnostic=p.stderr.replace(str(out), 'negative')))
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	assert not failures, failures
	print(f'{len(records)} rejection checks across {len(PARSER)+len(SEMANTIC)+len(FLOW)} cases')


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
