# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source admission, exact nominal compatibility, and intended diagnostics."""
from pathlib import Path
import json
import os
import subprocess
import sys

sys.dont_write_bytecode = True
PREFIX = 'enum E { Empty, Data(int left, int right), }\n'
NEGATIVE = {
	'empty': ('enum E {}', 'at least one'),
	'duplicate-type': ('enum E{A} enum E{B}', 'conflicting'),
	'duplicate-variant': ('enum E{A,A}', 'duplicate'),
	'duplicate-field': ('enum E{A(int a,int a)}', 'duplicate'),
	'unknown-field-type': ('enum E{A(Missing a)}', 'unknown'),
	'self-cycle': ('enum E{A(E a)}', 'cycle'),
	'indirect-cycle': ('enum E{A(F a)} enum F{B(E a)}', 'cycle'),
	'borrowed-field': ('enum E{A(borrowed void* a)}', 'payload'),
	'text-field': ('enum E{A(string a)}', 'copyable'),
	'slice-field': ('enum E{A(int[] a)}', 'copyable'),
	'class-field': ('class C{init(){}} enum E{A(C a)}', 'copyable'),
	'scalar-wrong-identity': (PREFIX+'void f(){var v=E.Data(true,1);}', 'int'),
	'unknown-variant': (PREFIX+'void f(){var v=E.Missing();}', 'variant'),
	'missing-fields': (PREFIX+'void f(){var v=E.Data(1);}', 'argument'),
	'extra-fields': (PREFIX+'void f(){var v=E.Empty(1);}', 'argument'),
	'no-constructor-parentheses': (PREFIX+'void f(){var v=E.Empty;}', 'enum'),
	'constructor-trailing-comma': (PREFIX+'void f(){var v=E.Data(1,2,);}', 'expression'),
	'constructor-named': (PREFIX+'void f(){var v=E.Data(left=1,right=2);}', "')'"),
	'declaration-semicolon': ('enum E{A};', 'declaration'),
	'nonexhaustive': (PREFIX+'void f(E e){match(e){case E.Empty():{}}}', 'nonexhaustive'),
	'duplicate-case': (PREFIX+'void f(E e){match(e){case E.Empty():{} case E.Empty():{} else:{}}}', 'duplicate'),
	'unknown-case': (PREFIX+'void f(E e){match(e){case E.Missing():{} else:{}}}', 'variant'),
	'wrong-case-enum': (PREFIX+'enum F{Empty} void f(E e){match(e){case F.Empty():{} else:{}}}', 'exact'),
	'after-else': (PREFIX+'void f(E e){match(e){else:{} case E.Empty():{}}}', 'last'),
	'redundant-else': (PREFIX+'void f(E e){match(e){case E.Empty():{} case E.Data(a,b):{} else:{}}}', 'unreachable'),
	'empty-match': (PREFIX+'void f(E e){match(e){}}', 'nonexhaustive'),
	'missing-bindings': (PREFIX+'void f(E e){match(e){case E.Data(a):{} else:{}}}', 'binding'),
	'mixed-pattern': (PREFIX+'void f(E e){match(e){case E.Data(left=a,b):{} else:{}}}', 'mix'),
	'unknown-named-field': (PREFIX+'void f(E e){match(e){case E.Data(missing=a,right=b):{} else:{}}}', 'field'),
	'duplicate-named-field': (PREFIX+'void f(E e){match(e){case E.Data(left=a,left=b):{} else:{}}}', 'duplicate'),
	'shadow-binding': (PREFIX+'void f(E e,int a){match(e){case E.Data(a,b):{} else:{}}}', 'shadow'),
	'duplicate-binding': (PREFIX+'void f(E e){match(e){case E.Data(a,a):{} else:{}}}', 'conflicts'),
	'escaped-binding': (PREFIX+'int f(E e){match(e){case E.Data(a,b):{} else:{}}return a;}', 'unknown'),
	'payload-equality': (PREFIX+'bool f(E a,E b){return a==b;}', 'payload enum equality'),
	'payload-free-nominal': ('enum A{X} enum B{X} bool f(A a,B b){return a==b;}', 'exact'),
	'nominal-assignment': ('enum A{X} enum B{X} void f(){A a=B.X();}', 'exact'),
	'nominal-argument': ('enum A{X} enum B{X} void use(A a){} void f(){use(B.X());}', 'exact'),
	'nominal-return': ('enum A{X} enum B{X} A f(){return B.X();}', 'exact'),
	'parameter-mutation': (PREFIX+'void f(E e){e=E.Empty();}', 'read-only'),
	'record-field': (PREFIX+'struct R{E e;}', 'field'),
	'class-storage-field': (PREFIX+'class C{E e;init(){}}', 'field'),
	'fixed-array': (PREFIX+'void f(){E[1] a={E.Empty()};}', 'element'),
	'owned-array': (PREFIX+'void f(){var a=new E[1];}', 'element'),
	'generic-record-enum-field': (PREFIX+'struct Box<T>{T value;} void f(){Box<E> b={value=E.Empty()};}', 'generic'),
	'c-parameter': (PREFIX+'extern(C) void f(E e);', 'enum'),
	'c-result': (PREFIX+'extern(C) E f();', 'enum'),
	'c-export': (PREFIX+'export(C) E f(){return E.Empty();}', 'enum'),
	'break-no-loop': (PREFIX+'void f(E e){match(e){else:{break;}}}', 'loop'),
	'continue-no-loop': (PREFIX+'void f(E e){match(e){else:{continue;}}}', 'loop'),
	'missing-return': (PREFIX+'int f(E e){match(e){case E.Empty():{return 1;} else:{}}}', 'return'),
	'unassigned-arm': (PREFIX+'class C{int a;init(E e){match(e){case E.Empty():{this.a=1;} else:{}}}}', 'initialized'),
	'guard': (PREFIX+'void f(E e){match(e){case E.Empty() if(true):{} else:{}}}', "':'"),
	'nested-pattern': (PREFIX+'void f(E e){match(e){case E.Data(E.Empty(),b):{} else:{}}}', "')'"),
	'exception-keyword-try': ('int try(){return 0;}', 'function name'),
	'exception-keyword-throw': ('int throw(){return 0;}', 'function name'),
	'exception-keyword-throws': ('int throws(){return 0;}', 'function name'),
	'exception-keyword-catch': ('int catch(){return 0;}', 'function name'),
	'async-keyword-name': ('int async(){return 0;}', 'function name'),
	'await-keyword-name': ('int await(){return 0;}', 'function name'),
}

POSITIVE = {
	'generic-enum': 'enum E<T>{A(T a)}',
	'owned-field': 'enum E{A(owned int[] a)}',
	'generic-argument': PREFIX+'void use<T>(T a){} void f(){use(E.Empty());}',
	'generic-signature': PREFIX+'void f<T>(E e,T x){}',

	'future-names-unreserved': 'int future(int capture,int Result,int Completion){return capture+Result+Completion;}',
	'zero-declarations': 'enum C{Red(),Blue,} bool f(C a){return a==C.Red()||a!=C.Blue();}',
	'qualifier-type-authority': PREFIX+'int f(){var E=E.Data(3,9);match(E){case E.Data(right=r,left=l):{return r-l;} else:{return 1;}}}',
	'field-name-reuse': 'enum E{A(int x),B(int x)} int f(E e){match(e){case E.A(x):{return x;} case E.B(x):{return -x;}}}',
	'discard': PREFIX+'int f(E e){match(e){case E.Data(_,b):{return b;} else:{return 0;}}}',
	'all-arms-assignment': PREFIX+'int f(E e){int x=0;match(e){case E.Data(a,b):{x=a+b;} else:{x=0;}}return x;}',
	'concrete-generic-record': 'struct Box<T>{T value;} enum E{Data(Box<int> b)} int f(){Box<int> b={value=7};var e=E.Data(b);match(e){case E.Data(x):{return x.value;}}}',
	'shared-nested-graph': 'enum A{X(int a)} enum B{X(A a,A b)} int f(){var a=A.X(3);var b=B.X(a,a);match(b){case B.X(x,y):{match(x){case A.X(v):{return v;}}}}}',
	'parameter-copy': PREFIX+'E f(E e){var x=e;x=E.Empty();return e;}',
	'methods-and-constructor': PREFIX+'struct S{int n;E relay(E e){return e;}} class C{int n;init(E e){match(e){case E.Data(a,b):{this.n=a+b;}else:{this.n=0;}}}E relay(E e){return e;}} int main(){S s={n=1};var e=s.relay(E.Data(2,3));C c=C.init(e);match(c.relay(e)){case E.Data(a,b):{return a+b-5;}else:{return 1;}}}',
	'old-generic-companion': PREFIX+'T id<T>(T x){return x;} int f(){var e=E.Data(id(2),id(3));match(e){case E.Data(a,b):{return a+b;}else:{return 0;}}}',
}

def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	results = []
	for accepted, cases in ((True, POSITIVE), (False, NEGATIVE)):
		for name, case in cases.items():
			code, reason = (case, '') if accepted else case
			path = out/(name+'.astra'); path.write_text(code+'\n')
			p = subprocess.run([str(compiler),'--check',str(path)], capture_output=True, text=True, env=dict(os.environ, CCACHE_DISABLE='1'))
			assert (p.returncode == 0) == accepted, (name, code, p.returncode, p.stderr)
			assert not p.stdout and (not accepted or not p.stderr), (name,p)
			assert accepted or reason in p.stderr, (name,reason,p.stderr)
			results.append(dict(name=name,accepted=accepted,diagnostic=p.stderr))
	(out/'results.json').write_text(json.dumps(results,indent=2)+'\n')
	print(json.dumps(dict(accepted=len(POSITIVE),rejected=len(NEGATIVE))))

if __name__ == '__main__':
	main(*(Path(arg).resolve() for arg in sys.argv[1:]))
