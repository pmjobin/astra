# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Direct-result exclusions, exact ownership and deterministic no-output gates."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HEADER = 'class C{init(){}}class D{init(){}}'
ECHO = 'owned T echo<T>(owned T v,int n) where T:Ownable{return move v;}'
SINK = 'int sink<T>(owned T v) where T:Ownable{return 0;}'
LOAN = 'int loan<T>(borrowed T v,int n) where T:Ownable{return n;}'
LAST = 'int last<T>(int n,borrowed T v) where T:Ownable{return n;}'
SCOPE = 'heap generic consumption requires one retained owned T'
CASES = {
	'alias-owner': (ECHO+'void bad(C alias){var r=echo<C>(move alias,0);}', 'nontransferable'),
	'borrowed-owner': (ECHO+'void bad(borrowed C alias){var r=echo<C>(move alias,0);}', 'nontransferable'),
	'wrong-class': (ECHO+'void bad(){var v=new C();var r=echo<D>(move v,0);}', 'requires exact type'),
	'upcast': ('class Base{init(){}}class Derived:Base{init():base(){}}'+ECHO+'void bad(){var v=new Derived();var r=echo<Base>(move v,0);}', 'requires exact type'),
	'plain-destination': (ECHO+'void bad(){var v=new C();C r=echo<C>(move v,0);}', 'carries ownership responsibility'),
	'discard': (ECHO+'void bad(){var v=new C();echo<C>(move v,0);}', 'carries ownership responsibility'),
	'generic-null-result': ('owned T echo<T>(owned T v) where T:Ownable{return null;}', 'copying and generic null'),
	'generic-copy-result': ('owned T echo<T>(owned T v) where T:Ownable{return v;}', 'copying and generic null'),
	'wrong-result-T': ('owned U echo<T,U>(owned T v) where T:Ownable where U:Ownable{return move v;}', 'exact result type parameter'),
	'local-lexical-escape': ('owned C bad(){owned C v=C.init();return move v;}', 'callee-local owned ObjectStorage cannot escape'),
	'new-generic-owner': ('owned T echo<T>(owned T v) where T:Ownable{return new T();}', 'owned T result requires explicit move'),
	'inline-new': (ECHO+'void bad(){var r=echo<C>(new C(),0);}', 'requires explicit'),
	'inline-result': (ECHO+'owned C make(){var v=new C();return move v;}void bad(){var r=echo<C>(make(),0);}', 'requires explicit'),
	'nested-consumer': (ECHO+SINK+'void bad(){var v=new C();sink<C>(echo<C>(move v,0));}', 'requires explicit'),
	'joined-owner': (ECHO+'void bad(bool b){var v=new C();if(b){var r=echo<C>(move v,0);}var s=echo<C>(move v,0);}', 'may have been moved'),
	'missing-return': ('owned T echo<T>(owned T v) where T:Ownable{}', 'every normal return path'),
	'invalid-early-exit': ('owned T echo<T>(owned T v,bool b) where T:Ownable{if(b){return;}return move v;}', 'requires'),
	'borrowed-result': ('owned T echo<T>(borrowed T v) where T:Ownable{return move v;}', 'requires one borrowed T'),
	'foreign-helper': ('extern(C) owned T echo<T>(owned T v) where T:Ownable;', 'generic extern(C) and export(C) functions are unsupported'),
	'generic-method': ('class Host{owned T echo<T>(owned T v) where T:Ownable{return move v;}}', 'generic members'),
	# M15 separately approved this unused declaration as the exact exit-42
	# historical-generic-owner-host positive in structural-generics-15.
	'aggregate': (ECHO+'void bad(){var v=new int[2];var r=echo<int[]>(move v,0);}', 'does not satisfy'),
	'owning-record': ('struct Record{owned C child;}'+ECHO+'void bad(borrowed C c){Record r={child=c};}', 'record Class replacement requires an exact heap owner move or owned factory result'),
}
RUNTIME = 'class AsyncError:Error{init(string s):base(s){}}enum RunStatus{Completed,Cancelled}async runtime VirtualExecutor throws AsyncError returns RunStatus;'
CASES['async-caller'] = (RUNTIME+ECHO+'async int bad(){var v=new C();var r=echo<C>(move v,0);return 0;}', 'requires a synchronous caller')
CASES['async-helper'] = (RUNTIME+'async owned T echo<T>(owned T v) where T:Ownable{return move v;}', 'generic async declarations are unsupported')
FLOW = set()
for spelling in ['<C>', '']:
	for name, body, diagnostic in [
		('caller-read-after-return', f'var r=echo{spelling}(move v,0);loan{spelling}(v,0);', 'cannot borrow moved'),
		('caller-duplicate-return', f'var r=echo{spelling}(move v,0);var s=echo{spelling}(move v,0);', 'moved'),
		('caller-release-after-return', f'var r=echo{spelling}(move v,0);release v;', 'moved'),
		('read-during-result-capture', f'var r=echo{spelling}(move v,loan{spelling}(v,0));', 'cannot borrow moved'),
	]:
		key = name + ('-explicit' if spelling else '-inferred')
		CASES[key] = (ECHO+LOAN+'void bad(){var v=new C();'+body+'}', diagnostic); FLOW.add(key)
for name, body in [
	('callee-consumed-before-return', 'sink<T>(move v);return move v;'),
	('callee-read-after-consumption', 'sink<T>(move v);loan<T>(v,0);return move v;'),
	('callee-overlap-left', 'loan<T>(v,sink<T>(move v));return move v;'),
	('callee-overlap-right', 'last<T>(sink<T>(move v),v);return move v;'),
]:
	CASES[name] = (SINK+LOAN+LAST+'owned T echo<T>(owned T v) where T:Ownable{'+body+'}', 'moved')


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	output = Path(tempfile.mkdtemp(prefix='attempt-', dir=output))
	rows, failures = [], []
	def check(name, inputs, diagnostic, modes):
		binary = output / (name + '-invalid'); assert not binary.exists()
		for mode in modes:
			command = [str(compiler), *([] if mode == 'native' else [mode]), *map(str, inputs), str(ROOT / 'lib/astra/base/errors.astra'), *(['-o', str(binary)] if mode == 'native' else [])]
			p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30, env=dict(os.environ, CCACHE_DISABLE='1'))
			valid = p.returncode == 1 and not p.stdout and diagnostic in p.stderr and 'internal error' not in p.stderr.lower() and not binary.exists()
			rows.append(dict(name=name, mode=mode, command=command, exit=p.returncode, stderr=p.stderr, passed=valid))
			if not valid: failures.append(rows[-1])
		(output / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
	modes = ['--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check', 'native']
	# Owning record declarations are accepted by the later record contracts.
	# Keep that old premise as an actual positive; reject copying a borrow above.
	positive = output / 'owning-record-current.astra'
	positive.write_text(HEADER + 'struct Record{owned C child;}' + ECHO + '\nint main(){return 42;}\n')
	positive_rows = []
	for mode in modes:
		binary = output / 'owning-record-current'
		command = [str(compiler), *([] if mode == 'native' else [mode]), str(positive), *(['-o', str(binary)] if mode == 'native' else [])]
		p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30)
		positive_rows.append(dict(command=command, exit=p.returncode, stderr=p.stderr, passed=p.returncode == 0 and not p.stderr))
		assert positive_rows[-1]['passed'], positive_rows[-1]
		if mode == 'native':
			p = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
			positive_rows.append(dict(command=[str(binary)], exit=p.returncode, passed=p.returncode == 42 and not p.stdout and not p.stderr))
			assert positive_rows[-1]['passed'], positive_rows[-1]
	(output / 'positive-checks.json').write_text(json.dumps(positive_rows, indent=2) + '\n')
	for name, (source, diagnostic) in CASES.items():
		path = output / (name + '.astra'); path.write_text(HEADER + source + '\nint main(){return 42;}\n')
		check(name, [path], diagnostic, modes[3:] if name in FLOW or name == 'joined-owner' else modes)
		# Approved exact cycle permutations are exercised by historical-storage-cycles.py.
	assert not failures, json.dumps(failures, indent=2)
	print(f'{len(CASES)} source cases; {len(rows)} diagnostic/no-executable checks')


if __name__ == '__main__':
	main(*sys.argv[1:])
