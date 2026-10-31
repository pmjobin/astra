# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Finite local shape, ownership/loan liveness and deterministic no-output gates."""
from pathlib import Path
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SINK = 'int sink<T>(owned T v,int n) where T:Ownable{return n;}'
LOAN = 'int loan<T>(borrowed T v,int n) where T:Ownable{return n;}'
LAST = 'int last<T>(int n,borrowed T v) where T:Ownable{return n;}'
LOCAL = 'owned T current=move v;'
PREFIX = 'void bad<T>(owned T v) where T:Ownable{'
SHAPE = 'generic owned locals'
CASES = {
	'plain-T': (PREFIX+'T current=v;}', 'plain Ownable T locals'),
	'copy': (PREFIX+'owned T current=v;}', SHAPE),
	'null': (PREFIX+'owned T current=null;}', SHAPE),
	'uninitialized': (PREFIX+'owned T current;}', None),
	'borrowed': ('void bad<T>(borrowed T v) where T:Ownable{'+LOCAL+'}', SHAPE),
	'missing-input': ('void bad<T>() where T:Ownable{owned T current=null;}', SHAPE),
	'two-types': ('void bad<T,U>(owned T v) where T:Ownable where U:Ownable{owned U current=move v;}', SHAPE),
	'duplicate-name': (PREFIX+'owned T v=move v;}', 'conflicts with parameter'),
	'new-T': (PREFIX+'owned T current=new T();}', None),
	'rearm': (PREFIX+LOCAL+'current=move v;}', None),
	'partial': (PREFIX+LOCAL+'var part=move current.field;}', None),
	'old-source-read': (LOAN+PREFIX+LOCAL+'loan<T>(v,0);}', 'moved'),
	'old-source-move': (SINK+PREFIX+LOCAL+'sink<T>(move v,0);}', 'moved'),
	'local-read-after-call': (SINK+LOAN+PREFIX+LOCAL+'sink<T>(move current,0);loan<T>(current,0);}', 'moved'),
	'local-double-call': (SINK+PREFIX+LOCAL+'sink<T>(move current,0);sink<T>(move current,0);}', 'moved'),
	'local-release-after-call': (SINK+PREFIX+LOCAL+'sink<T>(move current,0);release current;}', None),
	'overlap-left': (SINK+LOAN+PREFIX+LOCAL+'loan<T>(current,sink<T>(move current,0));}', 'moved'),
	'overlap-right': (SINK+LAST+PREFIX+LOCAL+'last<T>(sink<T>(move current,0),current);}', 'moved'),
	'possible-move': (SINK+LOAN+'void bad<T>(owned T v,bool b) where T:Ownable{'+LOCAL+'if(b){sink<T>(move current,0);}loan<T>(current,0);}', 'moved'),
	'escaping-loan': (LOAN+PREFIX+LOCAL+'T alias=current;}', 'plain Ownable T locals'),
	'return-original-with-local': ('owned T bad<T>(owned T v) where T:Ownable{'+LOCAL+'return move v;}', 'moved'),
	# M15 separately approved this unused declaration as the exact exit-42
	# historical-unqualified-owner-field positive in structural-generics-15.
	'method': ('class Host{void bad<T>(owned T v) where T:Ownable{'+LOCAL+'}}', 'generic members'),
	'foreign': ('extern(C) void bad<T>(owned T v) where T:Ownable;', 'generic extern(C)'),
	'aggregate-T': ('void stage<T>(owned T v) where T:Ownable{'+LOCAL+'}void caller(){var a=new int[2];stage<int[]>(move a);}', 'does not satisfy'),
}


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	rows = []
	for name, (source, diagnostic) in CASES.items():
		path, binary = output / (name + '.astra'), output / (name + '-invalid')
		path.write_text(source + '\nint main(){return 42;}\n')
		assert not binary.exists()
		first = None
		for mode in ['--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check', 'native']:
			command = [str(compiler), *([] if mode == 'native' else [mode]), str(path), str(ROOT / 'lib/astra/base/errors.astra'), *(['-o', str(binary)] if mode == 'native' else [])]
			p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=30, env=dict(os.environ, CCACHE_DISABLE='1'))
			if first is None:
				first = p.stderr
			valid = p.returncode == 1 and not p.stdout and bool(p.stderr) and p.stderr == first and (diagnostic is None or diagnostic in p.stderr) and 'internal error' not in p.stderr.lower() and not binary.exists()
			rows.append(dict(name=name, command=command, exit=p.returncode, stderr=p.stderr, passed=valid))
			(output / 'checks.json').write_text(json.dumps(rows, indent=2) + '\n')
			assert valid, rows[-1]
	print(f'{len(CASES)} source negatives; {len(rows)} deterministic rejection/no-executable gates')


if __name__ == '__main__':
	main(*sys.argv[1:])
