# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public native shared/weak lifetime evidence; outputs remain external."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
TRACE = '1:17\n5:1\n2:17\n5:2\n3:0\n4:0\nallocations=4 frees=4 payloads=2 blocks=2\n'
MEMORY_TRACE = TRACE.replace('allocations=4 frees=4 payloads=2 blocks=2', 'memory destructors=2')
PREFIX = 'class P{int value;init(int value){this.value=value;}}'
NEGATIVES = {
	'acquire-borrow': PREFIX+'int bad(borrowed P p){var s=shared_acquire(move p);return 0;}int main(){return 0;}',
	'acquire-lexical': PREFIX+'int main(){owned P p=P.init(7);var s=shared_acquire(move p);return 0;}',
	'moved-shared-use': PREFIX+'int main(){var p=new P(7);var s=shared_acquire(move p);var alias=s;var invalid=shared_clone(s);return 0;}',
	'double-acquire': PREFIX+'int main(){var p=new P(7);var s=shared_acquire(move p);var t=shared_acquire(move p);return 0;}',
	'use-moved-shared': PREFIX+'int main(){var p=new P(7);var s=shared_acquire(move p);var t=move s;var q=shared_clone(s);return 0;}',
	'borrow-weak': PREFIX+'int read(borrowed P p){return p.value;}int main(){var p=new P(7);var s=shared_acquire(move p);var w=shared_downgrade(s);return read(shared_borrow(w));}',
	'borrow-escape': PREFIX+'int main(){var p=new P(7);var s=shared_acquire(move p);var escaped=shared_borrow(s);return 0;}',
	'wrong-flavor': PREFIX+'int main(){var p=new P(7);var s=shared_acquire(move p);var w=weak_clone(s);return 0;}',
	'wrong-payload': PREFIX+'class Q{init(){}}int main(){var p=new P(7);owned Shared<Q> s=shared_acquire(move p);return 0;}',
	'nonclass': 'int main(){owned Shared<int> s=null;return 0;}',
	'foreign-shared': PREFIX+'extern(C) int foreign(borrowed Shared<P> p);int main(){return 0;}',
	'unowned-field': PREFIX+'class Holder{Shared<P> p;init(){}}int main(){return 0;}',
	'field-payload-loan': PREFIX+'class Holder{private owned Shared<P> p;init(owned Shared<P> p){this.p=move p;}int read(){return inspect(shared_borrow(this.p));}}int inspect(borrowed P p){return p.value;}int main(){return 0;}',
	'borrow-and-consume': PREFIX+'int inspect(borrowed P p,owned Shared<P> s){return p.value;}int main(){var p=new P(7);var s=shared_acquire(move p);return inspect(shared_borrow(s),move s);}',
}
DIAGNOSTICS = {
	'acquire-borrow': 'nontransferable', 'acquire-lexical': 'independently allocated exact Class owner',
	'moved-shared-use': "use of moved owned value 's'", 'double-acquire': "use of moved owned value 'p'",
	'use-moved-shared': "use of moved owned value 's'", 'borrow-weak': 'incompatible strong/weak handle capability',
	'borrow-escape': 'cannot be stored or returned', 'wrong-flavor': 'incompatible strong/weak handle capability',
	'wrong-payload': "expected initializer of type 'Shared<Q>'", 'nonclass': 'exact concrete nongeneric native Class',
	'foreign-shared': 'cannot cross a C boundary', 'unowned-field': 'resource-valued struct fields are unsupported',
	'field-payload-loan': 'explicit strong clone local', 'borrow-and-consume': 'forbids moving its backing strong handle',
}

def main(compiler, output):
	compiler, output = Path(compiler).resolve(), Path(output).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	rows, products = [], {}
	def run(command, expected=0, stdout=None):
		command = list(map(str, command))
		p = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
			timeout=120, env=dict(os.environ, CCACHE_DISABLE='1'))
		ok = p.returncode == expected and (stdout is None or p.stdout == stdout)
		if expected:
			ok &= 'internal error' not in p.stderr.lower() and bool(p.stderr)
		rows.append(dict(command=command, exit=p.returncode, stdout=p.stdout,
			stderr=p.stderr, status='PASS' if ok else 'FAIL'))
		(output/'checks.json').write_text(json.dumps(rows, indent=2)+'\n')
		assert ok, rows[-1]
		return p
	observer = output/'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'observer.c', '-o', observer], stdout='')
	for mode in ('O0', 'O1', 'O2'):
		product = output/('lifetime-'+mode)
		run([compiler, '-'+mode, HERE/'lifetime.astra', '--link-object', observer, '-o', product], stdout='')
		run([product], stdout=TRACE)
		products[product.name] = hashlib.sha256(product.read_bytes()).hexdigest()
	object_file = output/'lifetime.o'
	object_product = output/'lifetime-object'
	run([compiler, '-O2', '-c', HERE/'lifetime.astra', '-o', object_file], stdout='')
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', HERE/'object-client.c', object_file, observer, '-o', object_product], stdout='')
	run([object_product], stdout=TRACE)
	products[object_file.name] = hashlib.sha256(object_file.read_bytes()).hexdigest()
	products[object_product.name] = hashlib.sha256(object_product.read_bytes()).hexdigest()
	unique_observer = output/'unique-observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'unique-observer.c', '-o', unique_observer], stdout='')
	unique_trace = '1:1\n1:2\n2:2\n2:1\nunique allocations=2 frees=2 controls=0\n'
	for mode in ('O0', 'O1', 'O2'):
		product = output/('unique-control-'+mode)
		run([compiler, '-'+mode, HERE/'unique-control.astra', '--link-object', unique_observer, '-o', product], stdout='')
		run([product], stdout=unique_trace)
		products[product.name] = hashlib.sha256(product.read_bytes()).hexdigest()
	unique_ir = run([compiler, '--dump-llvm', HERE/'unique-control.astra']).stdout
	assert not any(marker in unique_ir for marker in ('shared.block', 'shared.increment', 'shared.decrement', 'shared.member'))
	(output/'unique-control.ll').write_text(unique_ir)
	for name, source in NEGATIVES.items():
		path = output/(name+'.astra'); path.write_text(source+'\n')
		p = run([compiler, '--check', path], expected=1)
		assert DIAGNOSTICS[name] in p.stderr, (name, p.stderr)
	plain_observer = output/'plain-observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'apps-observer.c', '-o', plain_observer], stdout='')
	fixtures = {'captures': '1:12\n3:0\n2:12\n', 'checked': '1:10\n2:10\n3:1\n4:-1\n',
		'stress': '1:5\n3:50000\n2:5\n', 'weak-backedge': '1:1\n1:2\n3:1\n2:1\n4:-1\n2:2\n'}
	for name, trace in fixtures.items():
		sources = [HERE/(name+'.astra')]
		if name == 'checked':
			sources.append(ROOT/'lib/astra/base/errors.astra')
		for mode in ('O0', 'O1', 'O2'):
			product = output/(name+'-'+mode)
			run([compiler, '-'+mode, *sources, '--link-object', plain_observer, '-o', product], stdout='')
			run([product], stdout=trace)
			products[product.name] = hashlib.sha256(product.read_bytes()).hexdigest()
		if shutil.which('valgrind'):
			p = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
				'--show-leak-kinds=all', '--errors-for-leak-kinds=all', output/(name+'-O2')], stdout=trace)
			assert 'ERROR SUMMARY: 0 errors' in p.stderr and 'in use at exit: 0 bytes in 0 blocks' in p.stderr
	if shutil.which('valgrind'):
		memory_observer = output/'memory-observer.o'
		run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-DSHARED_MEMORY_ONLY', '-c', HERE/'observer.c', '-o', memory_observer], stdout='')
		memory_product = output/'lifetime-memory'
		run([compiler, '-O2', HERE/'lifetime.astra', '--link-object', memory_observer, '-o', memory_product], stdout='')
		products[memory_product.name] = hashlib.sha256(memory_product.read_bytes()).hexdigest()
		p = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', memory_product], stdout=MEMORY_TRACE)
		assert 'ERROR SUMMARY: 0 errors' in p.stderr and 'in use at exit: 0 bytes in 0 blocks' in p.stderr
	sources = {name: hashlib.sha256((HERE/name).read_bytes()).hexdigest()
		for name in ('lifetime.astra', 'captures.astra', 'checked.astra', 'stress.astra',
		'weak-backedge.astra', 'unique-control.astra', 'unique-observer.c', 'object-client.c', 'observer.c', 'apps-observer.c', 'qualify.py')}
	(output/'result.json').write_text(json.dumps(dict(status='PASS', checks=rows,
		products=products, sources=sources, compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest()), indent=2)+'\n')
	print('native Shared/Weak source, O0/O1/O2 lifetime, refusals and memory checks passed')

if __name__ == '__main__':
	main(*sys.argv[1:])
