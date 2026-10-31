# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Ownership, lifetime, eligibility and ABI rejection at public boundaries."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PRELUDE = 'void use(f64[] a){} int take(owned f64[] a){return 0;} owned f64[] make(){return new f64[2];}\n'
CLASS = 'class C{owned f64[] a;init(){this.a=new f64[2];}int change(){this.a=new f64[3];return 0;}}\n'
CASES = {
	'owner-erasure': ('void f(){f64[] a=new f64[2];}', 'owning'),
	'owner-copy': ('void f(){owned f64[] a=make();owned f64[] b=a;}', 'move'),
	'persistent-borrow': ('void f(){owned f64[] a=make();f64[] b=a;}', 'borrow'),
	'borrow-return': ('f64[] f(){owned f64[] a=make();return a;}', 'slice'),
	'named-call-copy': ('void f(){owned f64[] a=make();take(a);}', 'move'),
	'named-return-copy': ('owned f64[] f(){owned f64[] a=make();return a;}', 'move'),
	'self-move': ('void f(){owned f64[] a=make();a=move a;}', 'self'),
	'double-move': ('void f(){owned f64[] a=make();owned f64[] b=move a;owned f64[] c=move a;}', 'moved'),
	'moved-index': ('void f(){owned f64[] a=make();take(move a);f64 x=a[0];}', 'moved'),
	'moved-length': ('void f(){owned f64[] a=make();take(move a);int n=len(a);}', 'moved'),
	'moved-borrow': ('void f(){owned f64[] a=make();take(move a);use(a);}', 'moved'),
	'released-index': ('void f(){owned f64[] a=make();release a;f64 x=a[0];}', 'released'),
	'overlap-index': ('void f(){owned f64[] a=make();f64 x=a[take(move a)];}', 'moved'),
	'overlap-argument': ('void pair(f64[] a,int b){}void f(){owned f64[] a=make();pair(a,take(move a));}', 'borrow'),
	'incompatible': ('void f(){owned f64[] a=make();owned f32[] b=new f32[2];a=move b;}', 'exact'),
	'negative-count': ('void f(){owned f64[] a=new f64[-1];}', 'negative'),
	'i128-deferred': ('void f(){owned i128[] a=new i128[2];}', 'unknown'),
	'u128-deferred': ('void f(){owned u128[] a=new u128[2];}', 'unknown'),
	'wrong-count': ('void f(u32 n){owned f64[] a=new f64[n];}', 'int'),
	'float-count': ('void f(){owned f64[] a=new f64[2.0];}', 'int'),
	'null-owner': ('void f(){owned f64[] a=null;}', 'no null state'),
	'discard-owner': ('void f(){make();}', 'discard'),
	'discard-allocation': ('void f(){new f64[2];}', 'expected'),
	'resource-element': ('void f(){owned R[] a=new R[2];}', 'element'),
	'class-element': ('class K{}void f(){owned K[] a=new K[2];}', 'element'),
	'typed-pointer-element': ('void f(){owned int*[] a=new int*[2];}', 'element'),
	'slice-element': ('void f(){owned f64[][] a=new f64[][2];}', 'array'),
	'array-element': ('void f(){owned f64[2][] a=new f64[2][2];}', 'array'),
	'type-parameter-element': ('void f<T>(int n){owned T[] a=new T[n];}', 'element'),
	'field-explicit-init': ('class K{owned f64[] a;}', 'explicit constructor'),
	'field-missing': ('class K{owned f64[] a;init(){}}', 'not definitely initialized'),
	'field-partial': ('class K{owned f64[] a;init(bool b){if(b){this.a=make();}}}', 'not definitely initialized'),
	'field-duplicate': ('class K{owned f64[] a;init(){this.a=make();this.a=make();}}', 'initialized twice'),
	'field-before-init': ('class K{owned f64[] a;init(){int n=len(this.a);this.a=new f64[n];}}', 'read before'),
	'field-move-out': (CLASS+'void f(borrowed C c){owned f64[] a=move c.a;}', 'moving ownership out'),
	'field-release': (CLASS+'void f(borrowed C c){release c.a;}', 'explicit release of an owned field'),
	'field-copy': (CLASS+'void f(borrowed C c){owned f64[] a=c.a;}', 'copying'),
	'field-persistent-borrow': (CLASS+'void f(borrowed C c){f64[] a=c.a;}', 'escaping'),
	'field-to-field': (CLASS+'void f(borrowed C a,borrowed C b){a.a=move b.a;}', 'moving ownership out'),
	'field-overlap-index': (CLASS+'void f(borrowed C c){f64 x=c.a[c.change()];}', 'overlaps'),
	'field-overlap-rhs': (CLASS+'f64 change(borrowed C c){c.change();return 1.0;}void f(borrowed C c){c.a[0]=change(c);}', 'overlaps'),
	'field-overlap-call': (CLASS+'void pair(f64[] a,borrowed C c){}void f(borrowed C c){pair(c.a,c);}', 'overlaps'),
	'owned-property': ('class C{property owned f64[] p{get{return new f64[2];}}}', 'owned property requires'),
	'resource-self-move': ('void f(){owned R r=resource(1);r=move r;}', 'self'),
	'resource-double-move': ('void f(){owned R r=resource(1);owned R s=move r;r=move s;s=move s;}', 'self'),
	'c-export-parameter': ('export(C) void consume(owned f64[] a){}', 'C ownership boundaries'),
	'c-export-result': ('export(C) owned f64[] produce(){return make();}', 'slice results are unsupported'),
}


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True); records = []
	# STRUCT-ELEM-1 and the approved wide-scalar extension qualify these elements.
	for name, source in [('struct-element', 'struct S{int x;}void f(){owned S[] a=new S[2];}'), ('generic-struct-element', 'struct S<T>{T x;}void f(){owned S<int>[] a=new S<int>[2];}'), ('i64-element', 'void f(){owned i64[] a=new i64[2];a[0]=-9223372036854775808;}'), ('u64-element', 'void f(){owned u64[] a=new u64[2];a[0]=18446744073709551615;}')]:
		path = out/(name+'.astra'); path.write_text(PRELUDE+source+'\n')
		for stage in ['cfg', 'ssa', 'nabi', 'llvm']:
			result = subprocess.run([compiler, '--dump-'+stage, path, '--vapi', ROOT/'tests/buffer/fixtures/runtime.vapi'], capture_output=True, text=True)
			assert result.returncode == 0 and result.stdout and not result.stderr, (name, stage, result)
			records.append(dict(name=name, stage=stage, diagnostic='', accepted=True))
	for name, (source, message) in CASES.items():
		path = out/(name+'.astra'); path.write_text(PRELUDE+source+'\n')
		for stage in ['cfg', 'ssa', 'nabi', 'llvm']:
			result = subprocess.run([compiler, '--dump-'+stage, path, '--vapi', ROOT/'tests/buffer/fixtures/runtime.vapi'], capture_output=True, text=True)
			assert result.returncode == 1 and not result.stdout and message.lower() in result.stderr.lower(), (name, stage, result.returncode, result.stdout, result.stderr, message)
			records.append(dict(name=name, stage=stage, diagnostic=result.stderr.strip()))
	plain = out/'vapi-main.astra'; plain.write_text('int main(){return 0;}\n')
	for name, source, message in [('vapi-owner-parameter', 'void consume(owned f64[] a);', 'expected VAPI parameter type'), ('vapi-owner-result', 'owned f64[] produce();', 'expected VAPI function name'), ('vapi-borrowed-slice', 'void consume(f64[] a);', 'expected VAPI parameter name')]:
		api = out/(name+'.vapi'); api.write_text(source+'\n')
		result = subprocess.run([compiler, '--check', plain, '--vapi', api], capture_output=True, text=True)
		assert result.returncode == 1 and not result.stdout and message in result.stderr, (name, result)
		records.append(dict(name=name, stage='vapi', diagnostic=result.stderr.strip()))
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f'{len(records)} exact rejection checks')


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
