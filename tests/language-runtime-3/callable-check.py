# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify the finite native callable-object slice through public routes."""
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
HEADER = 'class F{init(){}int invoke(int input){return input+1;}}'
NEGATIVES = {
	'moved-callable': (HEADER, 'var f=new F();var moved=move f;return f(1);', "use of moved owned value 'f'"),
	'double-capture': (HEADER, 'var f=new F();var moved=move f;var second=move f;', "use of moved owned value 'f'"),
	'copy-owner': (HEADER, 'var f=new F();F copy=f;', 'persistent alias from owned ClassType'),
	'destroyed-callable': (HEADER, 'var f=new F();release f;return f(1);', "use of released owned value 'f'"),
	'loan-escape': (HEADER, 'F outer=null;{F inner=F.init();outer=inner;}return outer(1);', 'shorter lexical lifetime'),
	'borrow-result': (HEADER+'F escape(borrowed F f){return f;}', '', 'object-reference results are unsupported'),
	'borrow-capture-field': (HEADER+'class Capture{F captured;}', '', 'object-reference fields are unsupported'),
	'borrow-consume': (HEADER+'int bad(F view,owned F owner){return view(1);}', 'var f=new F();return bad(f,move f);', "cannot borrow moved owned value 'f'"),
	'wrong-argument': (HEADER, 'F f=F.init();return f(true);', "expects type 'int'"),
	'missing-invoke': ('class F{init(){}}', 'F f=F.init();return f(1);', "requires a typed invoke method"),
	'throwing-effect': ('class F{init(){}int invoke(int input)throws Error{throw new Error("failure");}}', 'F f=F.init();return f(1);', 'unhandled checked exception'),
}
TRACES = {
	'nocapture': '',
	'borrowed': '1:10\n2:3\n',
	'owned': '1:10\n3:100\n4:100\n2:10\n1:20\n3:200\n4:200\n2:20\n1:30\n3:300\n4:300\n2:30\n5:0\n',
	'interface': '',
}


def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT), 'generated outputs must remain outside the source tree'
	output.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	rows = []

	def run(command, stdout=None, diagnostic=None, memory=False):
		command = list(map(str, command))
		result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = result.returncode != 0 if diagnostic else result.returncode == 0
		valid &= stdout is None or result.stdout == stdout
		if diagnostic:
			valid &= diagnostic in result.stderr and 'internal error' not in result.stderr.lower()
		elif memory:
			valid &= ('ERROR SUMMARY: 0 errors' in result.stderr
				and 'in use at exit: 0 bytes in 0 blocks' in result.stderr
				and '(suppressed: 0 from 0)' in result.stderr)
		else:
			valid &= not result.stderr
		rows.append(dict(command=command, exit=result.returncode, stdout=result.stdout,
			stderr=result.stderr, status='PASS' if valid else 'FAIL'))
		(output/'checks.json').write_text(json.dumps(rows, indent=2)+'\n')
		assert valid, rows[-1]
		return result.stdout

	observer = output/'callable-observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'callable-observer.c', '-o', observer], stdout='')
	products = {}
	for name, trace in TRACES.items():
		sources = [HERE/('callable-'+name+'.astra')]
		if name == 'nocapture':
			sources += [HERE/'callable-functions.astra']
		if name == 'owned':
			sources += [ROOT/'lib/astra/base/errors.astra']
		links = ['--link-object', observer] if name in ('borrowed', 'owned') else []
		ir = run([compiler, '--dump-llvm', *sources])
		(output/(name+'.ll')).write_text(ir)
		if name in ('nocapture', 'borrowed'):
			assert not re.search(r'\bcall [^\n]*@(?:calloc|malloc|realloc)\(', ir), 'lexical environment allocated heap storage'
		for mode in ('O0', 'O1', 'O2'):
			product = output/(name+'-'+mode)
			run([compiler, '-'+mode, *sources, *links, '-o', product], stdout='')
			run([product], stdout=trace)
			products[product.name] = hashlib.sha256(product.read_bytes()).hexdigest()
		if shutil.which('valgrind'):
			run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
				'--show-leak-kinds=all', '--errors-for-leak-kinds=all', output/(name+'-O2')], stdout=trace, memory=True)

	for name, (declarations, body, diagnostic) in NEGATIVES.items():
		source = output/('negative-'+name+'.astra')
		source.write_text(declarations+'int main(){'+body+'return 0;}\n')
		extras = [ROOT/'lib/astra/base/errors.astra'] if name == 'throwing-effect' else []
		run([compiler, '--check', source, *extras], diagnostic=diagnostic)
	(output/'products.json').write_text(json.dumps(products, indent=2)+'\n')
	print(f'PASS callable objects: {len(rows)} checks; {len(products)} public products; memory={bool(shutil.which("valgrind"))}')


if __name__ == '__main__':
	main(*sys.argv[1:])
