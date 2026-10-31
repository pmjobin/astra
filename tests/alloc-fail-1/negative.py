# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Allocation-clause diagnostics, including statically checked terminal paths."""
from pathlib import Path
import json
import subprocess
import sys

PRELUDE = 'void report(int n){}int value(){return 0;}owned T[] make<T>(int n){return new T[n] else report(n);}void take(owned int[] a){}'
CASES = {
	'block': ('void bad(){var a=new int[2] else {report(2);};}', 'syntax', 'expected'),
	'non-call': ('void bad(){var a=new int[2] else 7;}', 'syntax', 'requires a direct'),
	'fallback-owner': ('void bad(){var a=new int[2] else new int[0];}', 'syntax', 'requires a direct'),
	'missing': ('void bad(){var a=new int[2] else;}', 'syntax', 'expected'),
	'duplicate': ('void bad(){var a=new int[2] else report(2) else report(3);}', 'syntax', 'duplicate'),
	'misplaced': ('void bad(){var a=(new int[2]) else report(2);}', 'syntax', 'expected'),
	'named-argument': ('void bad(){var a=new int[2] else report(n:2);}', 'syntax', 'expected'),
	'temporary-receiver': ('struct S{void report(){}}S get(){S s={};return s;}void bad(){var a=new int[2] else get().report();}', 'syntax', 'only text byte_length supports an expression receiver'),
	'non-void': ('void bad(){var a=new int[2] else value();}', 'semantics', 'exact void'),
	'owner-result': ('void bad(){var a=new int[2] else make<int>(0);}', 'semantics', 'ownership'),
	'wrong-argument': ('void bad(){var a=new int[2] else report(false);}', 'semantics', 'type'),
	'unknown-call-zero': ('void bad(){var a=new int[0] else missing(2);}', 'semantics', 'unknown function'),
	'unknown-argument-zero': ('void bad(){var a=new int[0] else report(missing);}', 'semantics', 'unknown name'),
	'own-initializer-zero': ('void bad(){var a=new int[0] else report(len(a));}', 'semantics', 'unknown name'),
	'late-binding': ('void bad(){var a=new int[2] else report(later);int later=3;}', 'semantics', 'unknown name'),
	'non-callable-local': ('void bad(){int callback=1;var a=new int[2] else callback();}', 'semantics', 'unknown function'),
	'wrong-receiver': ('void bad(){int x=1;var a=new int[2] else x.report();}', 'semantics', 'receiver'),
	'unknown-member': ('struct S{int x;}void bad(){S s={x=1};var a=new int[2] else s.missing();}', 'semantics', 'unknown method'),
	'count-u32': ('void bad(u32 n){var a=new int[n] else report(2);}', 'semantics', 'int/i32'),
	'count-negative': ('void bad(){var a=new int[-1] else report(2);}', 'semantics', 'non-negative'),
	'constant': ('const int count=new int[2] else report(2);', 'semantics', 'constant'),
	'fixed-array': ('void bad(){int[2] a=new int[2] else report(2);}', 'semantics', 'initializer'),
	'inline': ('void bad(){take(new int[2] else report(2));}', 'semantics', 'explicit'),
	'nonowning': ('void bad(){int[] a=new int[2] else report(2);}', 'semantics', 'owning destination'),
	'phantom': ('void bad(){owned int[] a=make(2);}', 'semantics', 'cannot infer'),
	'premise': ('void bad<T>(T x){owned T[] a=new T[2] else report(2);}', 'semantics', 'signature-derived'),
	'phantom-action': ('void action<T>(int n){}void bad(){var a=new int[2] else action(2);}', 'semantics', 'cannot infer'),
	'partial-generic': ('void action<T,U>(T a,U b){}void bad(){var a=new int[2] else action<int>(1,2);}', 'semantics', 'full ordered list'),
	'wrong-generic-return': ('T action<T>(T x){return x;}void bad(){var a=new int[2] else action(2);}', 'semantics', 'exact void'),
	'no-new-element': ('void bad(){var a=new string[2] else report(2);}', 'semantics', 'element'),
	'borrow-transfer': ('void both(int[] a,owned int[] b){}void bad(){var old=new int[1];var a=new int[2] else both(old,move old);}', 'cfg', 'borrow'),
	'moved-zero': ('void bad(){var old=new int[1];take(move old);var a=new int[0] else report(len(old));}', 'cfg', 'moved'),
	'generic-moved-zero': ('void consume<T>(owned T[] a){}void bad<T>(owned T[] old){consume(move old);owned T[] a=new T[0] else report(len(old));}', 'semantics', 'generic definition'),
	'generic-double-move': ('void consume<T>(owned T[] a,owned T[] b){}void bad<T>(owned T[] old){owned T[] a=new T[0] else consume(move old,move old);}', 'semantics', "use of moved owned value 'old'"),
	'method-consumes-receiver': ('class C{init(){}void report(owned C other){}}void bad(){var c=C.init();var a=new int[2] else c.report(move c);}', 'cfg', 'receiver'),
	'captured-containing-owner': ('class C{owned int[] a;init(){this.a=new int[1];}}void consume(owned C c){}void bad(){var c=C.init();c.a=new int[2] else consume(move c);}', 'semantics', 'overlap'),
	'field-overlap': ('class C{owned int[] a;init(){this.a=new int[1];}}void consume(int[] a,owned C c){}void bad(){var c=C.init();c.a=new int[2] else consume(c.a,move c);}', 'semantics', 'overlap'),
}
POSITIVES = {
	'parentheses-and-if': 'int main(){if(true){var a=new int[0] else ((report(0)));}else{report(1);}return 0;}',
	'generic-action': 'void action<T>(T value){}int main(){var a=new int[0] else action<int>(2);var b=new int[0] else action(2);return 0;}',
	'independent-move': 'int main(){var old=new int[1];var a=new int[0] else take(move old);return len(old)-1;}',
	'generic-independent-move': 'void consume<T>(owned T[] a){}owned T[] alloc<T>(owned T[] old,int n){owned T[] a=new T[n] else consume(move old);report(len(old));return move a;}int main(){var old=new int[1];var a=alloc(move old,0);return len(a);}',
	'new-identifier': 'void new(int n){}int main(){var a=new int[0] else new(3);return 0;}',
	'old-owner-inspection': 'int main(){var a=new int[1];a=new int[0] else report(len(a));return len(a);}',
}


def qualify(compiler, out):
	out.mkdir(parents=True, exist_ok=False)
	rows = []
	failures = []
	for name, (source, stage, message) in CASES.items():
		(out / (name + '.astra')).write_text(PRELUDE + source + '\n')
		result = subprocess.run([compiler, '--dump-' + stage, name + '.astra'], cwd=out, capture_output=True)
		(out / (name + '.stderr')).write_bytes(result.stderr)
		rows.append(dict(name=name, stage=stage, status=result.returncode, diagnostic=result.stderr.decode()))
		if result.returncode != 1 or result.stdout or message.lower() not in result.stderr.decode().lower():
			failures.append(rows[-1] | {'expected': message})
	for name, source in POSITIVES.items():
		(out / (name + '.astra')).write_text(PRELUDE + source + '\n')
		result = subprocess.run([compiler, '--dump-llvm', name + '.astra'], cwd=out, capture_output=True)
		(out / (name + '.ll')).write_bytes(result.stdout)
		(out / (name + '.stderr')).write_bytes(result.stderr)
		rows.append(dict(name=name, stage='llvm', status=result.returncode, diagnostic=result.stderr.decode()))
		if result.returncode or result.stderr:
			failures.append(rows[-1])
	(out / 'results.json').write_text(json.dumps(rows, indent='\t') + '\n')
	assert not failures, json.dumps(failures, indent='\t')
	print(f'{len(CASES)} rejection witnesses; {len(POSITIVES)} positive controls')


if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	qualify(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
