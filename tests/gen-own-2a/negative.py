# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Finite heap consumer rejection gates and no executable production."""
from pathlib import Path
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HEADER = 'class C{init(){}}class D{init(){}}'
CONSUME = 'int consume<T>(owned T v,int n) where T:Ownable{return n;}'
LOAN = 'int borrow<T>(borrowed T v,int n) where T:Ownable{return n;}'
LAST = 'int last<T>(int n,borrowed T v) where T:Ownable{return n;}'
SCOPE = 'heap generic consumption requires one retained owned T'
RUNTIME = 'class AsyncError:Error{init(string s):base(s){}}enum RunStatus{Completed,Cancelled}async runtime VirtualExecutor throws AsyncError returns RunStatus;'
CASES = {
	# M15: approved scope promotions are preserved and exercised in
	# structural-generics-15/historical-storage-requirements.{json,py}.
	'owned-plus-borrowed': ('void two<T>(owned T a,borrowed T b) where T:Ownable{}void bad(){var a=new C();var b=new C();two<C>(move a,b);}', 'generic borrow helpers permit only copied scalar'),
	'missing-ownable': ('void bad<T>(owned T v){}', 'owned T requires explicit capability Ownable'),
	'plain-ownable': ('void bad<T>(T v) where T:Ownable{}', 'plain T value transport is unavailable'),
	'generic-null': (CONSUME+'void bad<T>(owned T v) where T:Ownable{consume<T>(null,0);}', 'Ownable T requires explicit move'),
	'inline-new': (CONSUME+'void bad(){consume<C>(new C(),0);}', 'requires explicit'),
	'inline-result': (CONSUME+'owned C make(){var v=new C();return move v;}void bad(){consume<C>(make(),0);}', 'requires explicit'),
	'alias-move': (CONSUME+'void bad(C v){consume<C>(move v,0);}', 'nontransferable'),
	'wrong-nominal': (CONSUME+'void bad(){var v=new C();consume<D>(move v,0);}', 'requires exact type'),
	'derived-upcast': ('class Base{init(){}}class Child:Base{init():base(){}}'+CONSUME+'void bad(){var v=new Child();consume<Base>(move v,0);}', 'requires exact type'),
	'array-owner': (CONSUME+'void bad(){var v=new int[2];consume<int[]>(move v,0);}', 'does not satisfy'),
	'async-caller': (RUNTIME+CONSUME+'async int bad(){var v=new C();return consume<C>(move v,0);}', 'requires a synchronous caller'),
	'async-helper': (RUNTIME+'async int consume<T>(owned T v) where T:Ownable{return 0;}', 'generic async declarations are unsupported'),
	'foreign-helper': ('extern(C) void consume<T>(owned T v) where T:Ownable;', 'generic extern(C) and export(C) functions are unsupported'),
	'borrow-return': ('T leak<T>(borrowed T v) where T:Ownable{return v;}', 'plain T value transport'),
	'borrow-move': ('void bad<T>(borrowed T v) where T:Ownable{consume<T>(move v,0);}'+CONSUME, 'borrowed T cannot be moved'),
	'borrow-local': ('void bad<T>(borrowed T v) where T:Ownable{T local=v;}', 'generic owned locals and plain Ownable T locals'),
	'generic-member': ('class Host{void bad<T>(owned T v) where T:Ownable{}}', 'generic members'),
	# M15 separately approved the unused generic Class and owner-field declarations.
	# Exact sources remain exercised exit-42 positives in structural-generics-15.
	'closure-capture': ('void bad<T>(owned T v) where T:Ownable{var callback=()=>v;}', 'expected'),
	'owner-array': ('void bad<T>(owned T v) where T:Ownable{T[1] values={v};}', 'array'),
	'owner-address': ('void bad<T>(owned T v) where T:Ownable{var pointer=&v;}', 'address-of an Ownable parameter is deferred'),
}
FLOW = set()
for spelling in ['<C>', '']:
	for name, body, diagnostic in [
		('nested-loan', f'borrow{spelling}(v,consume{spelling}(move v,0));', 'cannot borrow moved'),
		('reverse-loan', f'last{spelling}(consume{spelling}(move v,0),v);', 'cannot borrow moved'),
		('converted-loan', f'borrow{spelling}(v,(consume{spelling}(move v,0) as i8) as int);', 'cannot borrow moved'),
		('after-move', f'consume{spelling}(move v,0);borrow{spelling}(v,0);', 'cannot borrow moved'),
		('double-consume', f'consume{spelling}(move v,0);consume{spelling}(move v,0);', 'moved'),
		('release-after-move', f'consume{spelling}(move v,0);release v;', 'moved'),
		('branch-join', f'if(b){{consume{spelling}(move v,0);}}borrow{spelling}(v,0);', 'may have been moved'),
		('loop-backedge', f'while(b){{borrow{spelling}(v,0);consume{spelling}(move v,0);}}', 'may have been moved'),
	]:
		key = name + ('-explicit' if spelling else '-inferred')
		CASES[key] = (CONSUME+LOAN+LAST+'void bad(bool b){var v=new C();'+body+'}', diagnostic)
		FLOW.add(key)


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	rows, failures = [], []
	for name, (source, diagnostic) in CASES.items():
		path = output / (name + '.astra')
		path.write_text(HEADER+source+'\nint main(){return 42;}\n')
		binary = output / (name + '-invalid')
		assert not binary.exists()
		modes = ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check', 'native'] if name in FLOW else ['--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check', 'native']
		for mode in modes:
			command = [str(compiler), *([] if mode == 'native' else [mode]), str(path), str(ROOT/'lib/astra/base/errors.astra'), *(['-o', str(binary)] if mode == 'native' else [])]
			p = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=30, env=dict(os.environ, CCACHE_DISABLE='1'))
			valid = p.returncode == 1 and not p.stdout and diagnostic in p.stderr and 'internal error' not in p.stderr.lower() and not binary.exists()
			rows.append(dict(name=name, mode=mode, exit=p.returncode, stderr=p.stderr, passed=valid))
			if not valid: failures.append(rows[-1])
	(output/'checks.json').write_text(json.dumps(rows, indent=2)+'\n')
	assert not failures, json.dumps(failures, indent=2)
	print(f'{len(CASES)} source cases; {len(rows)} diagnostic/no-executable checks')


if __name__ == '__main__':
	main(*sys.argv[1:])
