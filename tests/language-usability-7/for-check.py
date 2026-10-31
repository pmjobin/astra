# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public loop execution and refusal controls; generated products stay outside source."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='for-', dir=output))
	sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
	rows = []
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler), checks=rows,
		source_sha256={str(p.relative_to(ROOT)): sha(p) for p in [HERE/'for-control.astra',
		HERE/'for-checked.astra', HERE/'comparison-chain.astra', HERE/'foreach-bag.astra', HERE/'with-control.astra', HERE/'with-explicit.astra', ROOT/'lib/astra/collections/bag.astra', ROOT/'lib/astra/base/errors.astra', HERE/'observer.c', HERE/'for-check.py']}, products={})
	def run(argv, expected=0, stdout=b'', negative=None, memory=False):
		argv = list(map(str, argv))
		p = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		valid = p.returncode == expected and p.stdout == stdout
		if negative:
			valid &= negative.encode() in p.stderr and b':1:' in p.stderr
		elif memory:
			valid &= all(x in p.stderr for x in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			valid &= not p.stderr
		rows.append(dict(command=argv, expected_exit=expected, actual_exit=p.returncode,
			stdout=p.stdout.decode(errors='replace'), stderr=p.stderr.decode(errors='replace'),
			passed=bool(valid)))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert valid, rows[-1]
	observer = out/'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', HERE/'observer.c', '-o', observer])
	expected = {
		'for-control': b'100\n200\n10\n500\n20\n300\n201\n11\n21\n301\n202\n12\n22\n402\n100\n200\n17\n27\n400\n',
		'for-checked': b'1\n-1\n90\n1\n2\n-2\n-1\n91\n1\n2\n-2\n30\n-1\n92\n',
		'comparison-chain': b'1\n2\n3\n4\n8\n7\n3\n2\n1\n10\n11\n12\n42\n50\n',
		'with-control': b'1\n11\n22\n2\n32\n41\n102\n101\n1\n11\n22\n2\n32\n41\n102\n90\n101\n91\n53\n92\n103\n',
		'with-explicit': b'1\n11\n22\n2\n32\n41\n102\n101\n1\n11\n22\n2\n32\n41\n102\n90\n101\n91\n53\n92\n103\n',
		'foreach-bag': b'1\n2\n3\n4\n1002\n102\n2002\n1004\n104\n2004\n201\n202\n203\n204\n101\n900\n901\n-4\n-3\n-2\n-1\n',
	}
	for name, trace in expected.items():
		sources = [HERE/(name+'.astra')]
		if name in ['for-checked', 'comparison-chain', 'foreach-bag', 'with-control', 'with-explicit']: sources += [ROOT/'lib/astra/base/errors.astra']
		if name == 'foreach-bag': sources += [ROOT/'lib/astra/collections/bag.astra']
		for opt in ['-O0', '-O1', '-O2']:
			exe = out/(name+opt)
			run([compiler, opt, *sources, '--link-object', observer, '-o', exe])
			receipt['products'][str(exe)] = sha(exe)
			run([exe], stdout=trace)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full',
				'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', exe],
				stdout=trace, memory=True)
	negative = {
		'chain-moved': ('class C {init(){} int value(){return 1;}} int consume(owned C c){return 2;} int main(){var c=new C(); if(0 < 1 < consume(move c)){} return c.value();}', 'owned'),
		'chain-float-width': ('bool f(f32 a,f64 b,f32 c){return a < b < c;} int main(){return 0;}', 'one exact scalar numeric type'),
		'chain-mixed': ('bool f(i32 a,u32 b,i32 c){return a < b < c;} int main(){return 0;}', 'one exact scalar numeric type'),
		'chain-vector': ('bool f(i32<4> a,i32<4> b,i32<4> c){return a < b < c;} int main(){return 0;}', 'one exact scalar numeric type'),
		'chain-bool': ('bool f(bool a,bool b,bool c){return a < b < c;} int main(){return 0;}', 'one exact scalar numeric type'),
		'chain-parentheses': ('int main(){if((1 < 2) < 3){return 0;}return 1;}', "operator '<' requires an 'int' operand"),
		'chain-skipped-invalid': ('int main(){if(3 < 2 < missing()){return 1;}return 0;}', "unknown function 'missing'"),
		'chain-missing-operand': ('int main(){if(1 < 2 < ){return 0;}return 1;}', 'expected expression'),
		'scope': ('int main() { for (int i = 0; i < 1; i = i + 1) {} return i; }', "unknown name 'i'"),
		'condition': ('int main() { for (; 1;) {} return 0; }', "for condition must have type 'bool'"),
		'body-local-step': ('int main() { for (;; j = 1) { int j = 0; break; } return 0; }', "unknown assignment target 'j'"),
		'step-declaration': ('int main() { for (;; int j = 1) {} return 0; }', 'for step requires an assignment or call'),
		'missing-separator': ('int main() { for (int i = 0; i < 1 i = i + 1) {} return 0; }', "expected ';' after for condition"),
		'moved-condition': ('class C { init() {} bool next() { return true; } } void consume(owned C value) {} int main() { var c = new C(); for (; c.next(); consume(move c)) {} return 0; }', 'owned'),
	}
	bag_prefix = 'class D {int tag; init(){this.tag=1;}} '
	for name, body, diagnostic in [
		('reserve', 'bag.reserve(10);', 'borrow'),
		('take', 'var taken=bag.take(0);', 'borrow'),
		('release', 'release bag;', 'active receiver or foreach'),
		('move', 'var moved=move bag;', 'cannot consume'),
		('copy', 'var alias=item;', 'call-scoped readonly inspection'),
		('field-write', 'item.tag=9;', 'call-scoped readonly helper'),
	]:
		negative['foreach-'+name] = (bag_prefix+'int main(){var bag=new Bag<D>();foreach(var item in bag){'+body+'}return 0;}', diagnostic)
	negative['foreach-mutator'] = (bag_prefix+'void mutate(D value){value.tag=9;} int main(){var bag=new Bag<D>();foreach(var item in bag){mutate(item);}return 0;}', 'readonly scoped inspector')
	negative['foreach-transitive-mutator'] = (bag_prefix+'void mutate(D value){value.tag=9;} void forward(D value){mutate(value);} int main(){var bag=new Bag<D>();foreach(var item in bag){forward(item);}return 0;}', 'readonly scoped inspector')
	negative['foreach-index-mutator'] = (bag_prefix+'void mutate(D value){value.tag=9;} int main(){var bag=new Bag<D>();foreach(var item in bag){mutate(bag.entries[0]);}return 0;}', 'readonly scoped inspector')
	negative['foreach-helper-alias'] = (bag_prefix+'void mutate(Bag<D> other){other.reserve(2);} int main(){var bag=new Bag<D>();foreach(var item in bag){mutate(bag);}return 0;}', 'borrow')
	negative['foreach-source'] = ('int main(){int value=3;foreach(var item in value){}return 0;}', 'named exact Bag')
	with_prefix = 'class C {int field; init(){this.field=1;} void mutate(){this.field=9;}} '
	for name, body, diagnostic in [
		('move', 'var moved=move config;', 'cannot consume'),
		('release', 'release config;', 'active receiver'),
		('copy', 'var alias=config;', 'persistent alias'),
		('field-write', 'config.field=9;', 'with receiver scope forbids'),
		('method-write', 'config.mutate();', 'readonly scoped inspector'),
		('rearm', 'config=make();', 'with receiver cannot be reassigned'),
		('shadow', 'var config=new C();', 'duplicate local'),
	]:
		negative['with-'+name] = (with_prefix+'owned C make(){var c=new C();return move c;} int main(){with(var config=make()){'+body+'}return 0;}', diagnostic)
	negative['with-free-mutator'] = (with_prefix+'void mutate(C value){value.field=9;} int main(){var config=new C();with(config){mutate(config);}return 0;}', 'readonly scoped inspector')
	negative['with-binding-scope'] = (with_prefix+'int main(){with(var config=new C()){}return config.field;}', "unknown name 'config'")
	negative['with-raw-expression'] = (with_prefix+'int main(){with(new C()){}return 0;}', "expected ')' after with receiver")
	negative['with-expired-owner'] = (with_prefix+'int main(){var config=new C();release config;with(config){}return 0;}', 'owned')
	negative['with-text-escape'] = ('class C {readonly string label; init(){this.label="hello";}} string escape(){with(var c=new C()){return c.label;}} int main(){return 0;}', 'borrowed text cannot escape')
	negative['with-scalar'] = ('int main(){int value=1;with(value){}return 0;}', 'named owned exact native Class')
	for name, (source, diagnostic) in negative.items():
		path = out/(name+'.astra'); path.write_text(source+'\n')
		run([compiler, '--check', path, *([ROOT/'lib/astra/collections/bag.astra'] if 'Bag<' in source else [])], expected=1, negative=diagnostic)
	print(f'{len(rows)} public loop/chain checks; receipts: {out}')


if __name__ == '__main__':
	main(*sys.argv[1:])
