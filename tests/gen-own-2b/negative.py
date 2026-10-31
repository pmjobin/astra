# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Forwarding scope, source-order cycles, live ownership and no output artifact."""
from pathlib import Path
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HEADER = 'class C{init(){}}class D{init(){}}'
SINK = 'int sink<T>(owned T v,int n) where T:Ownable{return n;}'
RELAY = 'int relay<T>(owned T v,int n) where T:Ownable{return sink<T>(move v,n);}'
LOAN = 'int loan<T>(borrowed T v,int n) where T:Ownable{return n;}'
LAST = 'int last<T>(int n,borrowed T v) where T:Ownable{return n;}'
SCOPE = 'heap generic consumption requires one retained owned T'
CASES = {
	# Q11D separately approved this loop-result replacement. Direct incoming
	# heap results receive independent positive controls in gen-own-2c.
	'intermediate-owned-local': (SINK+'void relay<T>(owned T v) where T:Ownable{owned T x=move v;owned T second=move x;sink<T>(move x,0);}', 'moved'),
	'inline-heap-producer': (SINK+RELAY+'void bad(){relay<C>(new C(),0);}', 'requires explicit'),
	'inline-owned-result': (SINK+RELAY+'owned C create(){var v=new C();return move v;}void bad(){relay<C>(create(),0);}', 'requires explicit'),
	'nested-owned-result': ('owned T result<T>(owned T v) where T:Ownable{return move v;}'+SINK+'void relay<T>(owned T v) where T:Ownable{sink<T>(result<T>(move v),0);}', 'requires explicit'),
	'borrowed-symbolic-owner': (SINK+'void relay<T>(borrowed T v) where T:Ownable{sink<T>(move v,0);}', 'borrowed T cannot be moved'),
	'nonowner-concrete-actual': (SINK+RELAY+'void bad(C alias){relay<C>(move alias,0);}', 'nontransferable'),
	'wrong-nominal-relay': (SINK+RELAY+'void bad(){var v=new C();relay<D>(move v,0);}', 'requires exact type'),
	'derived-upcast-relay': ('class B{init(){}}class Child:B{init():base(){}}'+SINK+RELAY+'void bad(){var v=new Child();relay<B>(move v,0);}', 'requires exact type'),
	'aggregate-relay': (SINK+RELAY+'void bad(){var v=new int[2];relay<int[]>(move v,0);}', 'does not satisfy'),
	'generic-member': ('class Host{void relay<T>(owned T v) where T:Ownable{}}', 'generic members'),
	'foreign-forwarder': ('extern(C) void relay<T>(owned T v) where T:Ownable;', 'generic extern(C) and export(C) functions are unsupported'),
}
FLOW = set()
for spelling in ['<C>', '']:
	for name, body, diagnostic in [
		('after-relay', f'relay{spelling}(move v,0);loan{spelling}(v,0);', 'cannot borrow moved'),
		('double-relay', f'relay{spelling}(move v,0);relay{spelling}(move v,0);', 'moved'),
		('release-after-relay', f'relay{spelling}(move v,0);release v;', 'moved'),
		('nested-loan', f'loan{spelling}(v,relay{spelling}(move v,0));', 'cannot borrow moved'),
		('reverse-loan', f'last{spelling}(relay{spelling}(move v,0),v);', 'cannot borrow moved'),
		('converted-loan', f'loan{spelling}(v,(relay{spelling}(move v,0) as i8) as int);', 'cannot borrow moved'),
		('branch-join', f'if(b){{relay{spelling}(move v,0);}}loan{spelling}(v,0);', 'may have been moved'),
		('loop-backedge', f'while(b){{relay{spelling}(move v,0);}}', 'may have been moved'),
	]:
		key = name + ('-explicit' if spelling else '-inferred')
		CASES[key] = (SINK+RELAY+LOAN+LAST+'void bad(bool b){var v=new C();'+body+'}', diagnostic)
		FLOW.add(key)
for name, body in [
	('generic-moved-read', 'sink<T>(move v,0);loan<T>(v,0);'),
	('generic-two-moves', 'sink<T>(move v,0);sink<T>(move v,0);'),
	('generic-overlap-left', 'loan<T>(v,sink<T>(move v,0));'),
	('generic-overlap-right', 'last<T>(sink<T>(move v,0),v);'),
	('generic-inferred-overlap', 'loan(v,sink(move v,0));'),
]:
	CASES[name] = (SINK+LOAN+LAST+'void relay<T>(owned T v) where T:Ownable{'+body+'}', 'moved')


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	rows, failures = [], []
	def check(name, inputs, diagnostic, modes):
		binary = output / (name + '-invalid')
		assert not binary.exists()
		for mode in modes:
			command = [str(compiler), *([] if mode == 'native' else [mode]), *map(str, inputs), str(ROOT/'lib/astra/base/errors.astra'), *(['-o', str(binary)] if mode == 'native' else [])]
			p = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, timeout=30, env=dict(os.environ, CCACHE_DISABLE='1'))
			valid = p.returncode == 1 and not p.stdout and diagnostic in p.stderr and 'internal error' not in p.stderr.lower() and not binary.exists()
			rows.append(dict(name=name, mode=mode, command=command, exit=p.returncode, stderr=p.stderr, passed=bool(valid)))
			if not valid: failures.append(rows[-1])
		(output/'checks.json').write_text(json.dumps(rows, indent=2)+'\n')
	all_modes = ['--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check', 'native']
	for name, (source, diagnostic) in CASES.items():
		path = output / (name + '.astra')
		path.write_text(HEADER+source+'\nint main(){return 42;}\n')
		check(name, [path], diagnostic, all_modes[3:] if name in FLOW else all_modes)
		# Approved exact cycle permutations are exercised by historical-storage-cycles.py.
	assert not failures, json.dumps(failures, indent=2)
	print(f'{len(CASES)} source cases; {len(rows)} diagnostic/no-executable checks')


if __name__ == '__main__':
	main(*sys.argv[1:])
