# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Unused definitions and concrete calls must preserve exact ownership contracts."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
LIBRARIES = [ROOT / 'lib/astra/base/slices.astra', ROOT / 'lib/astra/base/buffers.astra']
PRELUDE = 'struct Box<T>{T value;}struct A{int x;}struct B{int x;}owned T[] make<T>(int n){return new T[n];}owned T[] relay<T>(owned T[] a){return move a;}void consume<T>(owned T[] a){}T snapshot<T>(T[] a){return a[0];}int drop<T>(owned T[] a){return 0;}'
CASES = {
	'plain-t-premise': ('void bad<T>(T value){owned T[] a=new T[1];}', 'signature-derived'),
	'plain-t-allocation': ('void bad<T>(T value){var a=new T[1];}', 'signature-derived'),
	'foreign-premise': ('void bad<T,U>(T[] source){owned U[] a=new U[1];}', 'signature-derived'),
	'copy-owner': ('void bad<T>(owned T[] a){owned T[] b=a;}', 'cannot be copied'),
	'borrow-to-owner': ('owned T[] bad<T>(T[] a){return a;}', 'exact owned buffer result'),
	'borrow-move': ('void bad<T>(T[] a){consume(move a);}', 'move source'),
	'missing-move': ('void bad<T>(owned T[] a){consume(a);}', 'explicit'),
	'explicit-missing-move': ('void bad<T>(owned T[] a){consume<T>(a);}', 'explicit'),
	'double-move': ('void bad<T>(owned T[] a){consume(move a);consume(move a);}', 'generic definition'),
	'moved-len': ('void bad<T>(owned T[] a){consume(move a);var n=len(a);}', 'generic definition'),
	'moved-index': ('void bad<T>(owned T[] a){consume(move a);T v=a[0];}', 'generic definition'),
	'moved-borrow': ('void bad<T>(owned T[] a,T v){consume(move a);fill(a,v);}', 'generic definition'),
	'released-len': ('void bad<T>(owned T[] a){release a;var n=len(a);}', 'RELEASED'),
	'released-index': ('void bad<T>(owned T[] a){release a;T v=a[0];}', 'RELEASED'),
	'double-release': ('void bad<T>(owned T[] a){release a;release a;}', 'RELEASED'),
	'branch-move': ('void bad<T>(owned T[] a,bool b){if(b){consume(move a);}var n=len(a);}', 'generic definition'),
	'branch-release': ('void bad<T>(owned T[] a,bool b){if(b){release a;}T v=a[0];}', 'generic definition'),
	'loop-move': ('void bad<T>(owned T[] a,int n){var i=0;while(i<n){consume(move a);i=i+1;}}', 'generic definition'),
	'continue-move': ('void bad<T>(owned T[] a,bool b){while(b){consume(move a);continue;}}', 'generic definition'),
	'break-move': ('void bad<T>(owned T[] a,bool b){while(b){consume(move a);break;}var n=len(a);}', 'generic definition'),
	'local-loop': ('void bad<T>(T[] source,int n){owned T[] a=clone_array(source);var i=0;while(i<n){consume(move a);i=i+1;}}', 'generic definition'),
	'self-move': ('void bad<T>(owned T[] a){a=move a;}', 'self-move'),
	'return-borrow': ('owned T[] bad<T>(T[] source){return source;}', 'exact owned buffer result'),
	'missing-return': ('owned T[] bad<T>(int n){owned T[] a=new T[n];}', 'every normal return'),
	'conditional-return': ('owned T[] bad<T>(int n,bool b){if(b){return new T[n];}}', 'every normal return'),
	'wrong-return': ('owned T[] bad<T,U>(T[] source,U[] other){return clone_array(other);}', 'exact owned buffer result'),
	'dropped-result': ('void bad<T>(T[] a){clone_array(a);}', 'ownership responsibility'),
	'escaping-result': ('void bad<T>(T[] a){T[] view=clone_array(a);}', 'ownership responsibility'),
	'escaping-owner': ('void bad<T>(owned T[] a){T[] view=a;}', 'escaping slice'),
	'inline-new': ('void bad<T>(T[] a){consume(new T[1]);}', 'inline producers'),
	'inline-factory': ('void bad<T>(T[] a){consume(clone_array(a));}', 'inline producers'),
	'inline-explicit': ('void bad<T>(T[] a){consume<T>(new T[1]);}', 'explicit'),
	'inline-concrete': ('void concrete(owned int[] a){}void bad(){concrete(new int[1]);}', 'explicit'),
	'bare-identity': ('T identity<T>(T x){return x;}void bad(){var a=new int[1];identity(a);}', 'GEN1_PLAIN_COPY'),
	'ownable-slice': ('owned T forward<T>(owned T a) where T : Ownable{return move a;}void bad(){var a=new int[1];var b=forward<int[]>(move a);}', 'Ownable'),
	'ownable-elements': ('void bad<T>(owned T[] a) where T : Ownable{}', 'Ownable elements'),
	'ownable-borrow-count': ('void bad<T>(borrowed T a,borrowed T b) where T : Ownable{}', 'generic borrowing requires one borrowed T'),
	'constructed': ('void bad<T>(owned Box<T>[] a){}', 'signature-derived'),
	'symbolic-field': ('struct Bad<T>{owned T[] a;}', 'owned struct fields are unsupported'),
	'borrowed-result': ('T[] bad<T>(T[] a){return a;}', 'slice results'),
	'unresolved-var': ('void bad<T>(T[] a){var b=clone_array(a);}', 'unresolved'),
	'borrow-binding': ('void bad<T>(T[] a,T[] b){a=b;}', 'parameter'),
	'count-u32': ('owned T[] bad<T>(u32 n){return new T[n];}', 'int/i32'),
	'count-float': ('owned T[] bad<T>(f32 n){return new T[n];}', 'int/i32'),
	'count-bool': ('owned T[] bad<T>(bool n){return new T[n];}', 'int/i32'),
	'count-negative-literal': ('owned T[] bad<T>(){return new T[-1];}', 'non-negative'),
	'no-result-inference': ('void bad(){owned f64[] a=make(8);}', 'cannot infer'),
	'null-inference': ('void bad(){consume(null);}', 'named array owner'),
	'null-owner': ('owned T[] bad<T>(){return null;}', 'slice has no null'),
	'nominal-conflict': ('void both<T>(owned T[] a,T v){}void bad(B b){var a=new A[1];both(move a,b);}', 'conflicting inferred'),
	'float-conflict': ('void both<T>(owned T[] a,T v){}void bad(){var a=new f64[1];both(move a,1.0);}', 'conflicting inferred'),
	'string-element': ('void bad(){var a=filled_array(1,"x");}', 'GEN1_PLAIN_COPY'),
	'partial-types': ('void both<T,U>(owned T[] a,U value){}void bad(){var a=new int[1];both<int>(move a,1);}', 'full ordered list'),
	'same-call': ('void both<T>(T[] view,owned T[] a){}void bad<T>(owned T[] a){both(a,move a);}', 'generic definition'),
	'later-move': ('void both<T>(T[] view,int v){}void bad<T>(owned T[] a){both(a,drop(move a));}', 'generic definition'),
	'live-destination': ('T take<T>(owned T[] a){T saved=a[0];return saved;}void bad<T>(owned T[] a){a[0]=take(move a);}', 'generic definition'),
	'index-move': ('void bad<T>(owned T[] a){T value=a[drop(move a)];}', 'generic definition'),
	'field-later-transfer': ('class Owner{owned int[] a;init(){this.a=new int[2];}}int take_object<U>(owned U owner) where U : Ownable{return 1;}void bad<T>(T[] source){var object=Owner.init();object.a[0]=take_object(move object);}', 'temporary owned-field borrow overlaps'),
	'field-borrow-transfer': ('class Owner{owned int[] a;init(){this.a=new int[2];}}void take_both<T,U>(T[] source,owned U owner) where U : Ownable{}void bad<T>(T[] source){var object=Owner.init();take_both(object.a,move object);}', 'temporary owned-field borrow overlaps'),
}
SUPERSEDED = {
	'owned-formal': 'void valid<T>(owned T[] a){}',
	'owned-result': 'owned T[] valid<T>(T[] a){return clone_array(a);}',
	'owned-local': 'void valid<T>(T[] a){owned T[] b=new T[2];}',
	'direct-return': 'owned T[] valid<T>(int n){return new T[n];}',
}

def qualify(compiler, out):
	out.mkdir(parents=True, exist_ok=False)
	records = []
	failures = []
	for name, (text, diagnostic) in CASES.items():
		path = out / (name + '.astra')
		path.write_text(PRELUDE + text + '\n')
		for stage in ['semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'llvm']:
			result = subprocess.run([compiler, '--dump-' + stage, *LIBRARIES, path.name], cwd=out, capture_output=True, text=True)
			(out / (name + '.' + stage + '.stderr')).write_text(result.stderr)
			records.append(dict(name=name, stage=stage, status=result.returncode, diagnostic=result.stderr))
			if result.returncode != 1 or result.stdout or diagnostic.lower() not in result.stderr.lower() or 'syntax error' in result.stderr:
				failures.append((name, stage, diagnostic, result.stderr))
	for name, text in SUPERSEDED.items():
		path = out / (name + '.astra')
		path.write_text(PRELUDE + text + '\n')
		result = subprocess.run([compiler, '--dump-llvm', *LIBRARIES, path.name], cwd=out, capture_output=True, text=True)
		assert result.returncode == 0 and not result.stderr, (name, result)
		(out / (name + '.llvm')).write_text(result.stdout)
	(out / 'results.json').write_text(json.dumps(records, indent='\t') + '\n')
	assert not failures, failures
	print(f'{len(records)} definition and call rejections; {len(SUPERSEDED)} exact signature/operation supersessions')

if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
