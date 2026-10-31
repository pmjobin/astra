# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public grammar, exact diagnostic stages and owner/borrow composition controls."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CLASS = 'class C{owned int[] a;owned int[] b;init(){this.a=new int[2];this.b=new int[3];}int rotate(){swap(this.a,this.b);return 0;}}\n'
LOCALS = 'owned int[] a=new int[2];owned int[] b=new int[3];'
RECORD_CLASS = 'struct K{int n;int choose(int v){return this.n+v;}}class C{owned K[] a;owned K[] b;init(){this.a=new K[1];this.b=new K[2];}int rotate(){swap(this.a,this.b);return 0;}}'
CASES = {
	'missing-second': ('void f(){'+LOCALS+'swap(a);}', 'syntax', "exactly two owner operands separated by ','"),
	'extra-operand': ('void f(){'+LOCALS+'swap(a,b,a);}', 'syntax', "exactly two owner operands and ')'"),
	'missing-semicolon': ('void f(){'+LOCALS+'swap(a,b)}', 'syntax', "expected ';'"),
	'missing-parenthesis': ('void f(){'+LOCALS+'swap a,b;}', 'syntax', "expected '('"),
	'initializer-context': ('void f(){'+LOCALS+'var x=swap(a,b);}', 'syntax', 'expected expression'),
	'condition-context': ('void f(){'+LOCALS+'if(swap(a,b)){} }', 'syntax', 'expected expression'),
	'return-context': ('int f(){'+LOCALS+'return swap(a,b);}', 'syntax', 'expected expression'),
	'const-context': ('const int x=swap(a,b);', 'syntax', 'expected expression'),
	'reserved-callable': ('void swap(){}', 'syntax', 'function name'),
	'reserved-local': ('void f(){var swap=1;}', 'syntax', 'name'),
	'borrow-left': ('void f(int[] a){owned int[] b=new int[1];swap(a,b);}', 'semantics', 'owning buffer'),
	'borrow-right': ('void f(int[] b){owned int[] a=new int[1];swap(a,b);}', 'semantics', 'owning buffer'),
	'fixed-array': ('void f(){int[2] a={1,2};owned int[] b=new int[2];swap(a,b);}', 'semantics', 'owning buffer'),
	'indexed-element': ('void f(){'+LOCALS+'swap(a[0],b);}', 'semantics', 'owning buffer'),
	'allocation': ('void f(){'+LOCALS+'swap(new int[2],b);}', 'semantics', 'owning buffer'),
	'producer': ('owned int[] make(){return new int[2];}void f(){'+LOCALS+'swap(a,make());}', 'semantics', 'owning buffer'),
	'move-left': ('void f(){'+LOCALS+'swap(move a,b);}', 'syntax', "'move' is supported only as the direct initializer"),
	'move-right': ('void f(){'+LOCALS+'swap(a,move b);}', 'syntax', "'move' is supported only as the direct initializer"),
	'pointer-indirection': ('void f(int* p){owned int[] a=new int[2];swap(*p,a);}', 'semantics', 'owning buffer'),
	'constant': ('const int v=1;void f(){'+LOCALS+'swap(v,b);}', 'semantics', 'owning buffer'),
	'scalar': ('void f(){int a=1;int b=2;swap(a,b);}', 'semantics', 'owning buffer'),
	'wrong-element': ('void f(){owned int[] a=new int[2];owned u32[] b=new u32[3];swap(a,b);}', 'semantics', 'same exact canonical'),
	'nominal-records': ('struct A{int x;}struct B{int x;}void f(){var a=new A[2];var b=new B[3];swap(a,b);}', 'semantics', 'same exact canonical'),
	'array-subfield': ('struct R{int x;}void f(){var a=new R[2];var b=new R[3];swap(a[0].x,b);}', 'semantics', 'owning buffer'),
	'copy-value-field': ('struct R{int x;}void f(R r){var a=new int[2];swap(r.x,a);}', 'semantics', 'owning buffer'),
	'class-owner': ('class C{init(){}}void f(){var a=C.init();var b=C.init();swap(a,b);}', 'semantics', 'owning buffer'),
	'property': ('class C{owned int[] a;init(){this.a=new int[2];}property int n{get{return len(this.a);}}}void f(borrowed C c){var a=new int[1];swap(c.n,a);}', 'semantics', 'properties are not owner slots'),
	'uninitialized-field': ('class C{owned int[] a;owned int[] b;init(){this.a=new int[2];swap(this.a,this.b);this.b=new int[3];}}', 'semantics', 'read before'),
	'direct-field-move-remains': (CLASS+'void f(borrowed C c){owned int[] a=move c.a;}', 'semantics', 'moving ownership out'),
	'malformed-field-move': (CLASS+'void f(borrowed C c){owned int[] a=move c.;}', 'syntax', 'field'),
	'released-left': ('void f(){'+LOCALS+'release a;swap(a,b);}', 'core', 'RELEASED'),
	'released-right': ('void f(){'+LOCALS+'release b;swap(a,b);}', 'core', 'RELEASED'),
	'moved-left': ('void f(){'+LOCALS+'owned int[] c=move a;swap(a,b);}', 'core', 'MOVED'),
	'moved-right': ('void f(){'+LOCALS+'owned int[] c=move b;swap(a,b);}', 'core', 'MOVED'),
	'possibly-dead': ('void f(bool flag){'+LOCALS+'if(flag){release a;}swap(a,b);}', 'core', 'RELEASED'),
	'loop-dead': ('void f(bool flag){'+LOCALS+'while(flag){swap(a,b);release b;}}', 'core', 'RELEASED'),
	'generic-unmatched': ('void f<T,U>(owned T[] a,owned U[] b){swap(a,b);}', 'semantics', 'same exact canonical'),
	'generic-dead': ('void f<T>(owned T[] a,owned T[] b){release b;swap(a,b);}', 'semantics', 'RELEASED'),
	'generic-plain': ('void f<T>(T a,T b){swap(a,b);}', 'semantics', 'owning buffer'),
	'generic-ownable': ('void f<T>(owned T a,owned T b) where T : Ownable{swap(a,b);}', 'semantics', 'owning buffer'),
	'failure-call-context': ('void f(){'+LOCALS+'var c=new int[1] else swap(a,b);}', 'syntax', 'expected expression'),
	'persistent-local-view': ('void f(){'+LOCALS+'int[] view=a;swap(a,b);}', 'semantics', 'escaping'),
	'persistent-field-view': (CLASS+'void f(borrowed C c){int[] view=c.b;c.rotate();}', 'semantics', 'escaping'),
	'earlier-argument-left': (CLASS+'void use(int[] a,int v){}void f(borrowed C c){use(c.a,c.rotate());}', 'semantics', 'overlaps'),
	'earlier-argument-right': (CLASS+'void use(int[] a,int v){}void f(borrowed C c){use(c.b,c.rotate());}', 'semantics', 'overlaps'),
	'containing-alias': (CLASS+'void use(int[] a,int v){}void f(borrowed C a,borrowed C b){use(a.a,b.rotate());}', 'semantics', 'overlaps'),
	'destination-left': (CLASS+'void f(borrowed C c){c.a[0]=c.rotate();}', 'semantics', 'overlaps'),
	'destination-right': (CLASS+'void f(borrowed C c){c.b[0]=c.rotate();}', 'semantics', 'overlaps'),
	'index-left': (CLASS+'int f(borrowed C c){return c.a[c.rotate()];}', 'semantics', 'overlaps'),
	'index-right': (CLASS+'int f(borrowed C c){return c.b[c.rotate()];}', 'semantics', 'overlaps'),
	'indexed-receiver-left': (RECORD_CLASS+'int f(borrowed C c){return c.a[0].choose(c.rotate());}', 'semantics', 'overlaps'),
	'indexed-receiver-right': (RECORD_CLASS+'int f(borrowed C c){return c.b[0].choose(c.rotate());}', 'semantics', 'overlaps'),
	'earlier-local-view': ('void use(int[] view,int n){}int turn(owned int[] a,owned int[] b){swap(a,b);return len(a);}void f(){'+LOCALS+'use(a,turn(move a,move b));}', 'cfg', "cannot borrow moved owned value 'a'"),
}


def run(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	env = dict(os.environ, CCACHE_DISABLE='1', TMPDIR=str(out.resolve()))
	receipts, failures = [], []
	stages = ['syntax', 'semantics', 'core', 'cfg']
	for name, (source, stage, reason) in CASES.items():
		path = out / (name + '.astra')
		path.write_text(source + '\n')
		for selected in stages[:stages.index(stage) + 1]:
			command = [str(compiler), '--dump-' + selected, str(path)]
			result = subprocess.run(command, capture_output=True, env=env)
			(out / (name + '.' + selected + '.stdout')).write_bytes(result.stdout)
			(out / (name + '.' + selected + '.stderr')).write_bytes(result.stderr)
			expected = selected == stage
			okay = (result.returncode == 1 and not result.stdout and reason in result.stderr.decode()) if expected else (result.returncode == 0 and not result.stderr)
			receipts.append(dict(name=name, stage=selected, expected_rejection=expected, reason=reason if expected else None, command=command, status=result.returncode, passed=okay, source_sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
			if not okay:
				failures.append((name, selected, result.returncode, result.stderr.decode()))
				break
	fixture = ROOT / 'tests/own-swap-1/fixtures/slots.astra'
	for stage in ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']:
		command = [str(compiler), '--dump-' + stage, str(fixture)]
		result = subprocess.run(command, capture_output=True, env=env)
		(out / ('slots.' + stage + '.stdout')).write_bytes(result.stdout)
		(out / ('slots.' + stage + '.stderr')).write_bytes(result.stderr)
		okay = result.returncode == 0 and not result.stderr
		receipts.append(dict(name='slots', stage=stage, command=command, status=result.returncode, passed=okay))
		if not okay:
			failures.append(('slots', stage, result.returncode, result.stderr.decode()))
			break
	for name in ['slots', 'snapshot']:
		fixture = ROOT / 'tests/own-swap-1/fixtures' / (name + '.astra')
		command = [str(compiler), str(fixture), '-o', str(out / name)]
		result = subprocess.run(command, capture_output=True, env=env)
		(out / (name + '.compile.stdout')).write_bytes(result.stdout)
		(out / (name + '.compile.stderr')).write_bytes(result.stderr)
		okay = result.returncode == 0 and not result.stdout and not result.stderr
		receipts.append(dict(name=name, stage='compile', command=command, status=result.returncode, passed=okay))
		if not okay:
			failures.append((name, 'compile', result.returncode, result.stderr.decode()))
			continue
		result = subprocess.run([str(out / name)], capture_output=True, env=env)
		(out / (name + '.run.stdout')).write_bytes(result.stdout)
		(out / (name + '.run.stderr')).write_bytes(result.stderr)
		okay = result.returncode == 0 and not result.stdout and not result.stderr
		receipts.append(dict(name=name, stage='run', status=result.returncode, passed=okay))
		if not okay:
			failures.append((name, 'run', result.returncode, result.stderr.decode()))
			# Native token reservation does not alter the independent metadata grammar,
			# foreign external symbol strings or case-sensitive native identifiers.
	metadata = out / 'keyword-policy.vapi'; metadata.write_text('[CCode(cname="swap")] int foreign_name();\n[CCode(cname="metadata_swap")] int swap();\n')
	policy = out / 'keyword-policy.astra'; policy.write_text('int Swap(){return 1;}int SWAP(){return 2;}int f(){return foreign_name()+Swap()+SWAP();}\n')
	command = [str(compiler), '--dump-llvm', str(policy), '--vapi', str(metadata)]
	result = subprocess.run(command, capture_output=True, env=env)
	(out / 'keyword-policy.llvm').write_bytes(result.stdout); (out / 'keyword-policy.stderr').write_bytes(result.stderr)
	okay = result.returncode == 0 and not result.stderr and b'@swap(' in result.stdout
	receipts.append(dict(name='independent-keyword-policies', command=command, status=result.returncode, passed=okay))
	if not okay:
		failures.append(('keyword-policy', 'llvm', result.returncode, result.stderr.decode()))
	resource = out / 'resource.vapi'; resource.write_text('[CCode(destroy_function="drop_resource")] handle R;\n')
	resource_source = out / 'resource.astra'; resource_source.write_text('void f(owned R a,owned R b){swap(a,b);}\n')
	for stage in ['syntax', 'semantics']:
		command = [str(compiler), '--dump-' + stage, str(resource_source), *(['--vapi', str(resource)] if stage != 'syntax' else [])]
		result = subprocess.run(command, capture_output=True, env=env)
		(out / ('resource.' + stage + '.stdout')).write_bytes(result.stdout); (out / ('resource.' + stage + '.stderr')).write_bytes(result.stderr)
		okay = result.returncode == (0 if stage == 'syntax' else 1) and (not result.stderr if stage == 'syntax' else b'owning buffer' in result.stderr)
		receipts.append(dict(name='resource-owner-domain', command=command, stage=stage, status=result.returncode, passed=okay))
		if not okay:
			failures.append(('resource-owner-domain', stage, result.returncode, result.stderr.decode()))
	(out / 'receipt.json').write_text(json.dumps(receipts, indent='\t') + '\n')
	for failure in failures:
		print(failure)
	assert not failures, f'{len(failures)} source qualification failures'
	print(f'{len(receipts)} exact source-stage checks')


if __name__ == '__main__':
	run(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
