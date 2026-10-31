# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Finite native interfaces: real dispatch, owner movement, cleanup and refusals."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	rows = []

	def run(command, status=0, stdout=None, diagnostic=None, seed=None):
		env = os.environ.copy()
		if seed is not None:
			env['ASTRA_DISPATCH_SEED'] = str(seed)
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, timeout=90)
		row = dict(command=command, status=p.returncode, stdout=p.stdout.decode(errors='replace'),
			stderr=p.stderr.decode(errors='replace'), seed=seed)
		rows.append(row)
		(output/'dispatch-checks.json').write_text(json.dumps(dict(checks=rows), indent=2)+'\n')
		assert p.returncode == status, row
		if stdout is not None:
			assert p.stdout == stdout, row
		if diagnostic:
			assert diagnostic in row['stderr'], row
		return p

	for cc in ['gcc', 'clang']:
		if not shutil.which(cc):
			continue
		for memory in [False, True]:
			provider = output/f'{cc}-provider-{memory}.o'
			flags = ['-DDISPATCH_MEMORY_ONLY'] if memory else []
			run([cc, '-std=c11', '-Wall', '-Wextra', '-Werror', *flags, '-c', HERE/'dispatch-provider.c', '-o', provider])
			for opt in ['-O0', '-O1', '-O2']:
				executable = output/f'dispatch-{cc}-{memory}{opt}'
				run([compiler, opt, HERE/'dispatch.astra', '--link-object', provider, '-o', executable])
				for seed in [-7, 0, 4, 13]:
					selected = seed+108 if seed % 2 == 0 else seed*3+201
					expected = f'dispatch seed={seed} selected={selected} moved=1 drops=3121\n'.encode()
					command = [executable]
					if memory and shutil.which('valgrind'):
						command = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
							'--show-leak-kinds=all', '--errors-for-leak-kinds=all', executable]
					p = run(command, stdout=expected, seed=seed)
					if command[0] == 'valgrind':
						assert re.search(rb'in use at exit: 0 bytes in 0 blocks', p.stderr), p.stderr
						assert re.search(rb'ERROR SUMMARY: 0 errors', p.stderr), p.stderr
	contract = 'interface Read {int read(int n);} '
	positive = 'class Good:Read{init():base(){}override int read(int n){return n+1;}} '
	cases = {
		'missing': (contract+'class Missing:Read{init():base(){}}', 'must explicitly override'),
		'signature': (contract+'class Wrong:Read{init():base(){}override int read(bool n){return 0;}}', 'exact type'),
		'no-override': (contract+'class Wrong:Read{init():base(){}int read(int n){return n;}}', 'explicit override'),
		'duplicate': (contract+'class Wrong:Read{init():base(){}override int read(int n){return n;}override int read(int n){return n;}}', 'duplicate method'),
		'construct-heap': (contract+'int main(){var x=new Read();return 0;}', 'cannot be constructed'),
		'construct-lexical': (contract+'int main(){var x=Read.init();return 0;}', 'cannot be constructed'),
		'construct-brace': (contract+'int main(){Read x={};return 0;}', 'cannot be constructed'),
		'owned-parameter': (contract+'int consume(owned Read r){return 0;}', 'cannot consume an owner'),
		'owned-result': (contract+'owned Read make(){return null;}', 'owning interface results'),
		'mutating-implementation': (contract+'class Wrong:Read{int count;init():base(){this.count=0;}override int read(int n){this.count=n;return n;}}', 'read-only implementation'),
		'effectful-implementation': (contract+'int side(int n){return n;}class Wrong:Read{init():base(){}override int read(int n){return side(n);}}', 'read-only implementation'),
		'unknown-operation': (contract+'int inspect(Read r){return r.absent(1);}', 'unknown method'),
		'nominal-mismatch': (contract+'interface Other{int read(int n);}int inspect(Read r){return r.read(1);}int wrong(Other r){return inspect(r);}', 'expects type'),
		'abstract-no-receiver': (contract+'int main(){return Read.read(3);}', 'receiver'),
		'moved-owner': (contract+positive+'int inspect(Read r){return r.read(1);}int main(){var a=new Good();var b=move a;return inspect(a);}', 'moved'),
		'outside-scope': (contract+positive+'int main(){Read view=null;{var a=Good.init();view=a;}return view.read(1);}', None),
		'bad-contract-result': ('interface Wrong{bool read(int n);}', 'copied int results'),
		'bad-contract-param': ('interface Wrong{int read(bool n);}', 'copied int values'),
		'inherited-receiver-move': ('class Base{init(){}virtual int f(int n){return n;}}class Derived:Base{init():base(){}}int consume(owned Derived d){return 3;}int main(){var d=new Derived();return d.f(consume(move d));}', 'method receiver cannot consume'),
	}
	for name, (source, diagnostic) in cases.items():
		path = output/f'dispatch-negative-{name}.astra'
		path.write_text(source+'\n')
		for stage in ['--check', '--dump-llvm']:
			p = run([compiler, stage, path], status=1, diagnostic=diagnostic)
			assert not p.stdout, rows[-1]
			# Same spelling/signature in separate modules must retain nominal identity.
	left = output/'dispatch-left.astra'; right = output/'dispatch-right.astra'; client = output/'dispatch-client.astra'
	left.write_text('namespace Left;interface Read{int read(int n);}class Box:Read{init():base(){}override int read(int n){return n+1;}}int inspect(Read r){return r.read(9);}\n')
	right.write_text('namespace Right;interface Read{int read(int n);}class Box:Read{init():base(){}override int read(int n){return n+2;}}int inspect(Read r){return r.read(9);}\n')
	client.write_text('int main(){var left=new Left.Box();var right=new Right.Box();return Left.inspect(left)+Right.inspect(right)-21;}\n')
	reference = None
	for order in [[left, right, client], [client, right, left]]:
		semantics = run([compiler, '--dump-semantics', *order]).stdout
		if reference is None:
			reference = semantics
		assert semantics == reference
		for opt in ['-O0', '-O2']:
			executable = output/f'modules{opt}'
			run([compiler, opt, *order, '-o', executable]); run([executable], stdout=b'')
	client.write_text('int wrong(Right.Read r){return Left.inspect(r);}\n')
	run([compiler, '--check', left, right, client], status=1, diagnostic='expects type')
	(output/'dispatch-result.json').write_text(json.dumps(dict(passed=True, checks=len(rows),
		compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
		sources={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [HERE/'dispatch.astra', HERE/'dispatch-provider.c']}), indent=2)+'\n')
	print(f'{len(rows)} native interface checks passed')


if __name__ == '__main__':
	main(*sys.argv[1:])
