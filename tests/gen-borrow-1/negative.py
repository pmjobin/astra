# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bounded generic loan rejection at source, downstream CLI stages and emission."""
from pathlib import Path
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / 'tests/gen-borrow-1'
LOAN = 'void loan<T>(borrowed T value,int n) where T:Ownable{}'
LAST = 'void last<T>(int n,borrowed T value) where T:Ownable{}'
CONSUME = 'int consume<T>(owned T value) where T:Ownable{return 0;}'
C = 'class C{init(){}}'
RUNTIME = 'class AsyncError:Error{init(string s):base(s){}}enum RunStatus{Completed,Cancelled}async runtime VirtualExecutor throws AsyncError returns RunStatus;'
CASES = {
	'missing-ownable': ('void bad<T>(borrowed T v){}', 'borrowed T requires explicit capability Ownable'),
	'value-capability': ('void bad<T>(borrowed T v) where T:Eq{}', 'borrowed T requires explicit capability Ownable'),
	'mixed-capability': ('void bad<T>(borrowed T v) where T:Ownable,Eq{}', 'Ownable cannot combine'),
	'two-borrows': ('void bad<T>(borrowed T a,borrowed T b) where T:Ownable{}', 'requires one borrowed T'),
	'owned-neighbor': ('void bad<T>(borrowed T a,owned T b) where T:Ownable{}', 'only copied scalar adjacent'),
	'borrowed-class-neighbor': (C+'void bad<T>(borrowed T a,C b) where T:Ownable{}', 'only copied scalar adjacent'),
	'borrowed-resource-neighbor': ('void bad<T>(borrowed T a,R b) where T:Ownable{}', 'only copied scalar adjacent'),
	'plain-ownable': ('void bad<T>(T a) where T:Ownable{}', 'plain T value transport'),
	'owned-result': ('owned T bad<T>(borrowed T a) where T:Ownable{return move a;}', 'requires one borrowed T'),
	'handle-result': ('R bad<T>(borrowed T a) where T:Ownable{return null;}', 'requires one borrowed T'),
	'borrowed-return': ('borrowed T bad<T>(borrowed T a) where T:Ownable{return a;}', 'borrowed'),
	'async-signature': ('async int bad<T>(borrowed T a) where T:Ownable{return 0;}', 'generic async declarations are unsupported'),
	'async-caller': (RUNTIME+LOAN+'async int work(owned R v){loan<R>(v,0);return 42;}', 'requires a synchronous caller'),
	'await-in-call': (RUNTIME+LOAN+'async int child(){return 0;}async int work(owned R v) throws Error{loan<R>(v,await child());return 42;}', 'requires a synchronous caller'),
	'throwing-signature': ('void bad<T>(borrowed T a) throws Error where T:Ownable{}', 'requires one borrowed T'),
	'foreign-generic': ('extern(C) void bad<T>(borrowed T a);', 'generic extern(C) and export(C)'),
	'export-generic': ('export(C) void bad<T>(borrowed T a) where T:Ownable{}', 'generic extern(C) and export(C)'),
	'generic-member': ('class C{void bad<T>(borrowed T a) where T:Ownable{}}', 'generic members'),
	'closure-capture': ('void bad<T>(borrowed T a) where T:Ownable{var f=()=>a;}', 'expected'),
	'local-T': ('void bad<T>(borrowed T a) where T:Ownable{T copy=a;}', 'plain Ownable T locals'),
	'inferred-alias': ('void bad<T>(borrowed T a) where T:Ownable{var copy=a;}', 'cannot be stored'),
	'return-loan': ('int bad<T>(borrowed T a) where T:Ownable{return a;}', 'cannot be stored'),
	'move-loan': (CONSUME+'void bad<T>(borrowed T a) where T:Ownable{consume<T>(move a);}', 'borrowed T cannot be moved'),
	'implicit-consume': (CONSUME+'void bad<T>(borrowed T a) where T:Ownable{consume<T>(a);}', "requires explicit 'move owner'"),
	'release-loan': ('void bad<T>(borrowed T a) where T:Ownable{release a;}', "release operand 'a' must be an owned"),
	'address-loan': ('void bad<T>(borrowed T a) where T:Ownable{var p=&a;}', 'address borrow'),
	'field-loan': ('void bad<T>(borrowed T a) where T:Ownable{var x=a.id;}', 'Ownable grants no field'),
	'cast-loan': ('void bad<T>(borrowed T a) where T:Ownable{var p=a as void*;}', 'cannot be stored'),
	'plain-copy-loan': ('T id<T>(T a){return a;}void bad<T>(borrowed T a) where T:Ownable{id<T>(a);}', 'GEN-1 type argument'),
	'array-loan': ('void bad<T>(borrowed T a) where T:Ownable{T[1] items={a};}', 'array'),
	'symbolic-null': (LOAN+'void bad<T>() where T:Ownable{loan<T>(null,0);}', 'null cannot be contextualized'),
	'unowned-resource': (LOAN+'void bad(){R value=null;loan<R>(value,0);}', 'requires a live exact owner'),
	'copied-concrete-alias': (C+LOAN+'void bad(C value){C alias=value;loan<C>(alias,0);}', 'requires a live exact owner'),
	'wrong-nominal-resource': (LOAN+'void bad(owned R value){loan<S>(value,0);}', "expects type 'S', provided 'R'"),
	'wrong-nominal-class': (C+'class D{init(){}}'+LOAN+'void bad(owned C value){loan<D>(value,0);}', "expects type 'D', provided 'C'"),
	'subtype-adaptation': ('class Base{init(){}}class Child:Base{init():base(){}}'+LOAN+'void bad(){var c=new Child();loan<Base>(c,0);}', "expects type 'Base', provided 'Child'"),
	# M15: the approved heap-cycle declaration is preserved in historical-storage-cycles.json.
	'owned-class-alias': (C+LOAN+'void bad(owned C value){C alias=value;loan<C>(alias,0);}', 'persistent alias'),
	'child-field-projection': (C+'class Holder{owned C child;init(owned C child){this.child=move child;}}'+LOAN+'void bad(Holder owner){loan<C>(owner.child,0);}', 'requires a live exact owner'),
	'wrong-scalar-type': (LOAN+'void bad(){loan<int>(null,0);}', "does not satisfy capability 'Ownable'"),
	'wrong-pointer-type': (LOAN+'void bad(){loan<void*>(null,0);}', "does not satisfy capability 'Ownable'"),
	'wrong-slice-type': (LOAN+'void bad(){loan<int[]>(null,0);}', "does not satisfy capability 'Ownable'"),
	'wrong-record-type': ('struct Record{owned R value;}'+LOAN+'void bad(){loan<Record>(null,0);}', "does not satisfy capability 'Ownable'"),
	'move-as-borrow': (LOAN+'void bad(owned R value){loan<R>(move value,0);}', 'requires a live exact owner'),
	'inline-owned-producer': (LOAN+'void bad(){loan<R>(create_r(1),0);}', 'requires a live exact owner'),
	'inferred-inline-owned-producer': (LOAN+'void bad(){loan(create_r(1),0);}', 'requires a live exact owner'),
	'null-inference': (LOAN+'void bad(){loan(null,0);}', "does not satisfy capability 'Ownable'"),
}

# Milestone 15: separately approved exact source; original main still returns 42.
SUPERSEDED = {
	'generic-class': ('class C<T>{}', None),
	'borrowed-concrete-class': (C+LOAN+'void bad(C value){loan<C>(value,0);}', None),
}

for spelling in ['<T>', '']:
	for name, body in {
		'overlap-later': f'loan{spelling}(v,consume{spelling}(move v));',
		'overlap-earlier': f'last{spelling}(consume{spelling}(move v),v);',
		'overlap-converted': f'loan{spelling}(v,(consume{spelling}(move v) as i8) as int);',
		'after-move': f'consume{spelling}(move v);loan{spelling}(v,0);',
		'branch-join': f'if(b){{consume{spelling}(move v);}}loan{spelling}(v,0);',
		'loop-backedge': f'while(b){{loan{spelling}(v,0);consume{spelling}(move v);}}',
	}.items():
		diagnostic = "owned value 'v' may have been moved at generic definition checking (MAYBE_OWNED)" if name in ['branch-join','loop-backedge'] else 'use of moved owned value'
		CASES[name+('-explicit' if spelling else '-inferred')] = (LOAN+LAST+CONSUME+'void bad<T>(owned T v,bool b) where T:Ownable{'+body+'}', diagnostic)
for actual, prefix, declaration in [('R', '', 'owned R v=create_r(1);'), ('C', C, 'var v=new C();')]:
	for name, body in {
		'nested-consume': f'loan<{actual}>(v,consume(move v));',
		'reverse-consume': f'last<{actual}>(consume(move v),v);',
	}.items():
		# A concrete consumer retains the existing heap-domain inference.
		CASES[actual+'-'+name] = (prefix+LOAN+LAST+f'int consume(owned {actual} v){{return 0;}}void bad(){{'+declaration+body+'}', 'cannot borrow moved')


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	if output.is_relative_to(ROOT):
		raise ValueError('outputs must be outside source')
	output.mkdir(parents=True, exist_ok=True)
	rows, failures = [], []
	for name, (source, diagnostic) in (CASES | SUPERSEDED).items():
		path = output / (name + '.astra'); path.write_text(source+'\nint main(){return 42;}\n')
		if diagnostic is None:
			def positive(command, mode, expected=0, memory=False, dump=False):
				command = list(map(str, command))
				p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
					timeout=90, env=dict(os.environ, CCACHE_DISABLE='1'))
				valid = p.returncode == expected
				if memory:
					valid &= all(text in p.stderr for text in ['ERROR SUMMARY: 0 errors',
						'in use at exit: 0 bytes in 0 blocks', '(suppressed: 0 from 0)'])
				else:
					valid &= not p.stderr
				if not dump:
					valid &= not p.stdout
				rows.append(dict(name=name, mode=mode, exit=p.returncode,
					stderr=p.stderr, passed=bool(valid), superseded=True))
				(output/'checks.json').write_text(json.dumps(rows, indent=2)+'\n')
				assert valid, rows[-1]
			for mode in ['--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg',
				'--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']:
				positive([compiler, mode, path, ROOT/'lib/astra/base/errors.astra',
					'--vapi', FIXTURES/'resources.vapi'], mode, dump=mode!='--check')
			for level in ['-O0', '-O1', '-O2']:
				binary = output/(name+level)
				positive([compiler, level, path, ROOT/'lib/astra/base/errors.astra',
					'--vapi', FIXTURES/'resources.vapi', '-o', binary], level+'-compile')
				positive([binary], level+'-execute', expected=42)
				positive(['valgrind', '--default-suppressions=no', '--leak-check=full',
					'--show-leak-kinds=all', '--errors-for-leak-kinds=all',
					'--error-exitcode=99', binary], level+'-memory', expected=42, memory=True)
			continue
		binary = output / (name + '-invalid')
		if binary.exists():
			raise ValueError('negative executable path must be absent: '+str(binary))
			# Concrete owner liveness is established by the existing CFG fixed point;
			# symbolic owner liveness rejects earlier during definition checking.
		modes = ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check', 'native'] if name in ['R-nested-consume', 'R-reverse-consume', 'C-nested-consume', 'C-reverse-consume'] else ['--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check', 'native']
		for mode in modes:
			command = [str(compiler), *([] if mode == 'native' else [mode]), str(path), str(ROOT/'lib/astra/base/errors.astra'), '--vapi', str(FIXTURES/'resources.vapi'), *(['-o', str(binary)] if mode == 'native' else [])]
			p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30, env=dict(os.environ, CCACHE_DISABLE='1'))
			valid = p.returncode == 1 and not p.stdout and diagnostic in p.stderr and 'internal error' not in p.stderr.lower() and not binary.exists()
			rows.append(dict(name=name, mode=mode, exit=p.returncode, stderr=p.stderr, passed=valid))
			if not valid:
				failures.append(rows[-1])
	(output/'checks.json').write_text(json.dumps(rows, indent=2)+'\n')
	if failures:
		raise AssertionError(json.dumps(failures, indent=2))
	print(f'{len(CASES)} negative and {len(SUPERSEDED)} preserved positive source cases; {len(rows)} checks')


if __name__ == '__main__':
	main(*sys.argv[1:])
