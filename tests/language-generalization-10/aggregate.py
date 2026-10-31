# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Recursive ownership: independent traces, every rollback prefix and exits."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
VAPI = ROOT/'tests/own-field/fixtures/resources.vapi'


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='aggregate-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	inputs = [HERE/'aggregate.astra', HERE/'aggregate-class.astra', HERE/'aggregate-buffer.astra', HERE/'aggregate-record-buffer.astra', HERE/'take.astra', HERE/'take-flow.astra', HERE/'transport.astra', HERE/'aggregate.py', VAPI,
		HERE/'transport-buffer.astra', HERE/'enum-scalar.astra', HERE/'enum-text.astra', HERE/'enum-record.astra', ROOT/'tests/owned-state-6/record-resources.c', ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/text/utf8-message.astra']
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler),
		sources={str(path.relative_to(ROOT)): sha(path) for path in inputs}, checks=[], products={})

	def run(argv, expected=0, stdout=b'', diagnostic=None, memory=False):
		argv = list(map(str, argv))
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected and (stdout is None or result.stdout == stdout)
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
			passed &= b'internal ' not in result.stderr and b'assertion' not in result.stderr
		elif memory:
			passed &= all(text in result.stderr for text in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(command=argv, expected_exit=expected,
			actual_exit=result.returncode, stdout=result.stdout.decode(errors='replace'),
			stderr=result.stderr.decode(errors='replace'), passed=bool(passed)))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert passed, receipt['checks'][-1]
		return result.stdout

	observer = out/'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c',
		ROOT/'tests/owned-state-6/record-resources.c', '-o', observer])
	sources = ['--vapi', VAPI, HERE/'aggregate.astra', ROOT/'lib/astra/base/errors.astra']
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *sources], stdout=None)
	trace = '''D101 +1 D102 D103 +3 D104 +4 D105 +5 D106 D25 -5 -4 -3 -1
D101 D901
D101 +1 D102 -1 D902
D101 +1 D102 D103 -1 D903
D101 +1 D102 D103 +3 D104 -3 -1 D904
D101 +1 D102 D103 +3 D104 +4 D105 -4 -3 -1 D905
D101 +1 D102 D103 +3 D104 +4 D105 +5 D106 -5 -4 -3 -1 D906
+11 +12 +13 +0 -13 -12 -11
+11 +12 +13 +0 -13 -12 -11
+20 +30 -30 -20 +21 +31 -31 -21'''
	expected = ('\n'.join(trace.split())+'\n').encode()
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('aggregate'+level)
		run([compiler, level, *sources, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=expected)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
			stdout=expected, memory=True)

	class_trace = b'+5\nD205\n-5\n+2\n+1\n+3\n+4\nD18\n-4\nD203\n-3\nD201\n-1\n-2\n+2\n+1\nD201\n-1\n-2\nD900\n'
	class_sources = ['--vapi', VAPI, HERE/'aggregate-class.astra', ROOT/'lib/astra/base/errors.astra']
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('aggregate-class'+level)
		run([compiler, level, *class_sources, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=class_trace)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
			stdout=class_trace, memory=True)

	buffer_trace = '''D101 D301 D102 +2 D103 +3 D104 D105 +5 D106 D306 D107 +7 D108 D12 D207 -7 -5 -3 D202 -2
D101 D901
D101 D301 D102 D902
D101 D301 D102 +2 D103 D202 -2 D903
D101 D301 D102 +2 D103 +3 D104 -3 D202 -2 D904
D101 D301 D102 +2 D103 +3 D104 D105 -3 D202 -2 D905
D101 D301 D102 +2 D103 +3 D104 D105 +5 D106 -5 -3 D202 -2 D906
D101 D301 D102 +2 D103 +3 D104 D105 +5 D106 D306 D107 -5 -3 D202 -2 D907
D101 D301 D102 +2 D103 +3 D104 D105 +5 D106 D306 D107 +7 D108 D207 -7 -5 -3 D202 -2 D908'''
	buffer_expected = ('\n'.join(buffer_trace.split())+'\n').encode()
	buffer_sources = ['--vapi', VAPI, HERE/'aggregate-buffer.astra', ROOT/'lib/astra/base/errors.astra']
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *buffer_sources], stdout=None)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('aggregate-buffer'+level)
		run([compiler, level, *buffer_sources, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=buffer_expected)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
			stdout=buffer_expected, memory=True)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('aggregate-record-buffer'+level)
		run([compiler, level, '--vapi', VAPI, HERE/'aggregate-record-buffer.astra',
			'--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=b'D42\n')
		run(['valgrind', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
			stdout=b'D42\n', memory=True)

	take_trace = '''+1 +2 +3 D1 -1 D3 D203 -3 D3 +4 +5 +6 -2 +7 -4 D23 D205 -5 -6 -7
+1 +2 +3 D1 -1 D203 -3 -2 D900
+1 +2 +3 D1 -1 D3 D203 -3 D3 +4 +5 +6 -6 D2 -2 +9 +7 -4 D23 D205 -5 -9 -7'''
	take_expected = ('\n'.join(take_trace.split())+'\n').encode()
	take_sources = ['--vapi', VAPI, HERE/'take.astra', ROOT/'lib/astra/base/errors.astra']
	for stage in ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *take_sources], stdout=None)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('take'+level)
		run([compiler, level, *take_sources, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=take_expected)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
			stdout=take_expected, memory=True)

	flow_trace = '''+10 +11 -11 D10 D210 -10
+1 +2 D1 -1 +3 D1 D3 -3 +4 D2 D4 -4 +5 D3 +6 -5 D7 D202 -2 -6
+1 +2 D1 -1 +3 D1 D3 -3 +4 D2 D4 -4 +5 D3 -5 +6 D7 D202 -2 -6
+8 +9 D209 -9 -8
+8 +9 -8 D209 -9'''
	flow_expected = ('\n'.join(flow_trace.split())+'\n').encode()
	flow_sources = ['--vapi', VAPI, HERE/'take-flow.astra']
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *flow_sources], stdout=None)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('take-flow'+level)
		run([compiler, level, *flow_sources, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=flow_expected)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
			stdout=flow_expected, memory=True)

		# Independent ownership observer checks active replacement, two scalar kinds,
		# nested sums, ignored fields, checked rollback and Class result extraction.
	enum_trace = '+1 +2 -1 D2 D202 -2 +3 D3 -3 D500 +10 +11 D1 D211 -11 -10 +10 +11 D921 D211 -11 -10 +20 -20 D700 +24 D24 D224 -24'
	enum_expected = ('\n'.join(enum_trace.split())+'\n').encode()
	enum_sources = ['--vapi', VAPI, HERE/'enum-scalar.astra', ROOT/'lib/astra/base/errors.astra']
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *enum_sources], stdout=None)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('enum-scalar'+level)
		run([compiler, level, *enum_sources, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=enum_expected)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
			stdout=enum_expected, memory=True)

	text_sources = ['--vapi', VAPI, HERE/'enum-text.astra', ROOT/'lib/astra/text/utf8-message.astra', ROOT/'lib/astra/base/errors.astra']
	text_expected = b'D5\nD800\nD900\n'
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *text_sources], stdout=None)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('enum-text'+level)
		run([compiler, level, *text_sources, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=text_expected)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
			stdout=text_expected, memory=True)

	record_enum_trace = '+2 +1 D100 D20 D2 D202 -2 +4 D18 D204 -4 -1 +2 +1 D100 D909 D202 -2 -1 +11 +10 D211 -11 -10 D600 +21 +20 -20 D21 D221 -21 +41 +40 +51 +50 +60 -60 D251 -51 -50 D241 -41 -40 D700'
	record_enum_expected = ('\n'.join(record_enum_trace.split())+'\n').encode()
	record_enum_sources = ['--vapi', VAPI, HERE/'enum-record.astra', ROOT/'lib/astra/base/errors.astra']
	for enum_input in [enum_sources, text_sources, record_enum_sources]:
		semantics = run([compiler, '--dump-semantics', *enum_input], stdout=None)
		assert b'concrete-owning' in semantics, 'semantic dump mislabeled a move-only enum as copyable'
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *record_enum_sources], stdout=None)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('enum-record'+level)
		run([compiler, level, *record_enum_sources, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=record_enum_expected)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
			stdout=record_enum_expected, memory=True)

	transport_trace = '''+2 +3 +1 D17 D203 -3 -2 -1
+2 +3 +1 -1 D203 -3 -2 D901
+2 +3 +1 D203 -3 -2 -1 D902
+2 +3 +1 D3 D203 -3 +4 D16 D204 -4 -2 -1
+6 +7 +5 D9 -6 -5 D7 +13 +14 +12 D40 D56 D214 -14 -13 -12 +21 +22 +20 +23 D23 D223 -23 D222 -22 -21 -20 D207 -7'''
	transport_expected = ('\n'.join(transport_trace.split())+'\n').encode()
	transport_sources = ['--vapi', VAPI, HERE/'transport.astra', ROOT/'lib/astra/base/errors.astra']
	for stage in ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *transport_sources], stdout=None)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('transport'+level)
		run([compiler, level, *transport_sources, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=transport_expected)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
			stdout=transport_expected, memory=True)

	buffer_transport_trace = '''+2 +1 D7 D14 D202 -2 -1
+12 +11 D212 -12 -11 D901
+22 +21 D104 D222 -22 -21 D902
+31 +30 D704 D231 -31 -30 +41 +40 +42 D42 D242 -42 D241 -41 -40 D0 D1 D2'''
	buffer_transport_expected = ('\n'.join(buffer_transport_trace.split())+'\n').encode()
	buffer_transport_sources = ['--vapi', VAPI, HERE/'transport-buffer.astra', ROOT/'lib/astra/base/errors.astra']
	for stage in ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, *buffer_transport_sources], stdout=None)
	for level in ['-O0', '-O1', '-O2']:
		executable = out/('transport-buffer'+level)
		run([compiler, level, *buffer_transport_sources, '--link-object', observer, '-o', executable])
		receipt['products'][str(executable)] = sha(executable)
		run([executable], stdout=buffer_transport_expected)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full',
			'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
			stdout=buffer_transport_expected, memory=True)
	buffer_declarations = 'struct Data{owned int[] values;owned R resource;}Data factory(){Data value={values=new int[3],resource=make(1)};return move value;}void consume(Data value){}'
	for name, body, diagnostic in [
		('buffer-transport-copy', 'consume(value);', 'explicit move'),
		('buffer-transport-partial', 'var extracted=move value.values;consume(move value);', 'moved owned value'),
		('buffer-transport-reused', 'consume(move value);consume(move value);', 'moved'),
		('buffer-transport-return-copy', 'return value;', 'explicit move'),
	]:
		path, product = out/(name+'.astra'), out/name
		if name == 'buffer-transport-return-copy':
			path.write_text(buffer_declarations+'Data invalid(){var value=factory();'+body+'}int main(){return 0;}')
		else:
			path.write_text(buffer_declarations+'int main(){var value=factory();'+body+'return 0;}')
		run([compiler, '--vapi', VAPI, path, '-o', product], expected=1, diagnostic=diagnostic)
		assert not product.exists()

	declarations = 'struct Pair{owned R first;owned Other second;int tag;}struct Branch{Pair payload;}'
	local = 'Branch branch={payload={first=make(1),second=make_other(2),tag=3}};'
	for name, body, diagnostic in [
		('copy', 'var copied=branch;', 'copyable'),
		('moved-read', 'var moved=move branch;return branch.payload.tag;', 'moved'),
		('second-move', 'var moved=move branch;var again=move branch;', 'moved'),
		('moved-join', 'if(live()==2){var moved=move branch;}return branch.payload.tag;', 'may have been moved'),
		('field-copy', 'owned R value=branch.payload.first;', 'Resource field access'),
	]:
		path = out/(name+'.astra')
		path.write_text(declarations+'int main(){'+local+body+'return 0;}\n')
		product = out/name
		run([compiler, '--vapi', VAPI, path, '-o', product], expected=1, diagnostic=diagnostic)
		assert not product.exists()

	class_declaration = 'class Item{int code;init(int code){this.code=code;}}struct Box{owned Item child;}'
	transport_declarations = declarations+'void consume(Branch value){}void twice(Branch first,Branch second){}Branch fresh(){'+local+'return move branch;}'
	for name, body, diagnostic in [
		('transport-copy-argument', 'consume(branch);', 'explicit move'),
		('transport-fresh-argument', 'consume(fresh());', 'named owning record'),
		('transport-duplicate', 'twice(move branch,move branch);', 'duplicate'),
		('transport-reused', 'consume(move branch);return branch.payload.tag;', 'moved'),
		('transport-partial', 'var first=move branch.payload.first;consume(move branch);', 'moved'),
	]:
		path = out/(name+'.astra'); path.write_text(transport_declarations+'int main(){'+local+body+'return 0;}\n')
		product = out/name
		run([compiler, '--vapi', VAPI, path, '-o', product], expected=1, diagnostic=diagnostic)
		assert not product.exists()
	for name, source in [
		('method-moved', 'class Service{init(){}void broken(Branch value){var used=move value;mark(value.payload.tag);}}int main(){return 0;}'),
		('constructor-moved', 'class Service{init(Branch value){var used=move value;mark(value.payload.tag);}}int main(){return 0;}'),
		('constructor-argument-reused', 'class Service{init(Branch value){}}int main(){'+local+'var service=new Service(move branch);return branch.payload.tag;}'),
		('constructor-argument-duplicated', 'class Service{init(Branch first,Branch second){}}int main(){'+local+'var service=new Service(move branch,move branch);return 0;}'),
	]:
		path = out/(name+'.astra'); path.write_text(declarations+source+'\n')
		product = out/name
		run([compiler, '--vapi', VAPI, path, '-o', product], expected=1,
			diagnostic='duplicate' if name.endswith('duplicated') else 'moved')
		assert not product.exists()
	for name, source, diagnostic in [
		('class-copy', class_declaration+'int main(){var child=new Item(1);Box box={child=move child};var copied=box;return 0;}', 'copyable'),
		('class-lexical', class_declaration+'int main(){Item child=Item.init(1);Box box={child=move child};return 0;}', 'nontransferable'),
		('class-alias', class_declaration+'int main(){var child=new Item(1);Box box={child=move child};var alias=box.child;return 0;}', 'field access'),
	]:
		path = out/(name+'.astra'); path.write_text(source+'\n')
		product = out/name
		run([compiler, path, '-o', product], expected=1, diagnostic=diagnostic)
		assert not product.exists()
	buffer_declaration = 'struct Box{owned int[] data;}'
	for name, source, diagnostic in [
		('buffer-copy', buffer_declaration+'int main(){Box box={data=new int[2]};var copied=box;return 0;}', 'copyable'),
		('buffer-alias', buffer_declaration+'int main(){Box box={data=new int[2]};var alias=box.data;return 0;}', 'field access'),
		('buffer-incoming-reuse', buffer_declaration+'int main(){var data=new int[2];Box box={data=move data};release data;return 0;}', 'moved'),
		('buffer-duplicate-incoming', 'struct Pair{owned int[] a;owned int[] b;}int main(){var data=new int[2];Pair pair={a=move data,b=move data};return 0;}', 'moved'),
	]:
		path = out/(name+'.astra'); path.write_text(source+'\n')
		product = out/name
		run([compiler, path, '-o', product], expected=1, diagnostic=diagnostic)
		assert not product.exists()
	for name, body, diagnostic in [
		('take-twice', 'var a=move branch.payload.first;var b=move branch.payload.first;', 'moved'),
		('take-whole-partial', 'var a=move branch.payload.first;var whole=move branch;', 'moved'),
		('take-join', 'if(live()==2){var a=move branch.payload.first;}var whole=move branch;', 'moved'),
		('take-wrong-type', 'owned Other a=move branch.payload.first;', 'exact'),
		('take-scalar', 'var a=move branch.payload.tag;', 'owner leaf'),
		('take-after-whole', 'var whole=move branch;var a=move branch.payload.first;', 'moved'),
		('take-loop-hole', 'for(int i=0;i<2;i=i+1){var a=move branch.payload.first;release a;}', 'moved'),
		('replace-after-whole', 'var whole=move branch;branch.payload.first=make(3);', 'moved'),
		('replace-wrong-type', 'branch.payload.first=make_other(3);', 'exact'),
	]:
		path = out/(name+'.astra'); path.write_text(declarations+'int main(){'+local+body+'return 0;}\n')
		product = out/name
		run([compiler, '--vapi', VAPI, path, '-o', product], expected=1, diagnostic=diagnostic)
		assert not product.exists()
	enum_declarations = 'enum Owned{Ready(owned R value,int tag),Empty}void use(Owned value){}'
	for name, body, diagnostic in [
		('enum-copy', 'var copied=value;', 'move-only enum'),
		('enum-reused-owner', 'id(resource);', 'moved'),
		('enum-copy-owner', 'var invalid=Owned.Ready(resource,0);', 'explicit move'),
		('enum-inspection-loan', 'match(value){case Owned.Ready(view,_):{mark(id(view));}else:{}}', 'consuming match'),
		('enum-reused-value', 'use(move value);use(move value);', 'moved'),
	]:
		path, product = out/(name+'.astra'), out/name
		path.write_text(enum_declarations+'int main(){owned R resource=make(1);var value=Owned.Ready(move resource,0);'+body+'return 0;}')
		run([compiler, '--vapi', VAPI, path, '-o', product], expected=1, diagnostic=diagnostic)
		assert not product.exists()
	for name, source, diagnostic in [
		('enum-duplicate-owner', 'enum Owned{Ready(owned R a,owned R b)}int main(){owned R resource=make(1);var value=Owned.Ready(move resource,move resource);return 0;}', 'reserved'),
		('enum-wrong-resource', 'enum Owned{Ready(owned Other a)}int main(){owned R resource=make(1);var value=Owned.Ready(move resource);return 0;}', 'exact'),
		('enum-stack-class', 'class Item{init(){}}enum Owned{Ready(owned Item a)}int main(){Item child=Item.init();var value=Owned.Ready(move child);return 0;}', 'nontransferable'),
	]:
		path, product = out/(name+'.astra'), out/name
		path.write_text(source)
		run([compiler, '--vapi', VAPI, path, '-o', product], expected=1, diagnostic=diagnostic)
		assert not product.exists()
	record_enum_declarations = 'struct Box{owned R resource;owned int[] bytes;int tag;}enum Owned{Held(Box value),Empty}void use(Owned value){}'
	record_enum_local = 'Box box={resource=make(1),bytes=new int[1],tag=1};'
	for name, body, diagnostic in [
		('enum-record-copy-payload', 'var value=Owned.Held(box);', 'explicit move'),
		('enum-record-reused-source', 'var value=Owned.Held(move box);return box.tag;', 'moved'),
		('enum-record-partial-source', 'var bytes=move box.bytes;var value=Owned.Held(move box);', 'moved'),
		('enum-record-copy-value', 'var value=Owned.Held(move box);var copy=value;', 'move-only enum'),
		('enum-record-inspection', 'var value=Owned.Held(move box);match(value){case Owned.Held(record):{}else:{}}', 'consuming match'),
		('enum-record-reused-value', 'var value=Owned.Held(move box);use(move value);use(move value);', 'moved'),
	]:
		path, product = out/(name+'.astra'), out/name
		path.write_text(record_enum_declarations+'int main(){'+record_enum_local+body+'return 0;}')
		run([compiler, '--vapi', VAPI, path, '-o', product], expected=1, diagnostic=diagnostic)
		assert not product.exists()
	path, product = out/'enum-record-duplicate.astra', out/'enum-record-duplicate'
	path.write_text('struct Box{owned R resource;}enum Owned{Both(Box first,Box second)}int main(){Box box={resource=make(1)};var value=Owned.Both(move box,move box);return 0;}')
	run([compiler, '--vapi', VAPI, path, '-o', product], expected=1, diagnostic='reserved')
	assert not product.exists()
	print(f"{len(receipt['checks'])} recursive aggregate checks; receipts: {out}")


if __name__ == '__main__':
	main(*sys.argv[1:])
