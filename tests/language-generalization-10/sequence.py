# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public copied iteration: exact output, owner exits and semantic refusals."""
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
	compiler = Path(compiler_path).resolve()
	output = Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='sequence-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	inputs = [HERE/'sequence.astra', HERE/'iterator.astra', HERE/'iterator-source.astra', HERE/'iterator-record.astra', HERE/'sequence.py', HERE/'sequence-contracts.vala',
		ROOT/'tests/language-usability-7/observer.c', ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/collections/bag.astra', ROOT/'lib/astra/collections/vector.astra',
		HERE/'container-iteration.astra', ROOT/'tests/own-field/fixtures/resources.vapi', ROOT/'tests/owned-state-6/record-resources.c']
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler),
		sources={str(path.relative_to(ROOT)): sha(path) for path in inputs}, checks=[], products={})

	def run(argv, expected=0, stdout=b'', diagnostic=None, memory=False, dump=False):
		argv = list(map(str, argv))
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected and (dump or result.stdout == stdout)
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
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

	observer = out/'observer.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c',
		ROOT/'tests/language-usability-7/observer.c', '-o', observer])
	resources = out/'resources.o'
	run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-c',
		ROOT/'tests/owned-state-6/record-resources.c', '-o', resources])
	oracles = {
		'container-iteration': b'-304\n78\n1\n+1\n+2\n11\n+3\n-3\n-12\n-2\n-11\n-1\n900\n+4\n+0\n1\n-4\n',
		'sequence': b'8\n6\n104\n-104\n4\n0\n204\n-204\n900\n8\n18\n72\n',
		'iterator': b'78\n-9\n9\n-300\n-7\n-5\n-1\n-305\n1\n3\n-304\n900\n',
		'iterator-record': b'20\n-104\n10\n-103\n900\n',
	}
	run([compiler, '--format', '--check', HERE/'iterator-source.astra'])
	for name, expected in oracles.items():
		run([compiler, '--format', '--check', HERE/(name+'.astra')])
		sources = [HERE/(name+'.astra')]
		if name == 'iterator':
			sources.append(HERE/'iterator-source.astra')
		links = ['--link-object', observer]
		if name == 'container-iteration':
			sources += [HERE/'iterator-source.astra', ROOT/'lib/astra/collections/vector.astra',
				'--vapi', ROOT/'tests/own-field/fixtures/resources.vapi']
			links += ['--link-object', resources]
			for stage in ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
				run([compiler, stage, *sources, ROOT/'lib/astra/base/errors.astra'], dump=True)
		for level in ['-O0', '-O1', '-O2']:

			executable = out/(name+level)
			run([compiler, level, *sources, ROOT/'lib/astra/base/errors.astra',
				ROOT/'lib/astra/collections/bag.astra', *links, '-o', executable])
			receipt['products'][str(executable)] = sha(executable)
			run([executable], stdout=expected)
			run(['valgrind', '--default-suppressions=no', '--leak-check=full',
				'--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--error-exitcode=99', executable],
				stdout=expected, memory=True)

	negative = {
		'release': ('release values;', 'active receiver or foreach collection'),
		'move': ('var next=move values;', 'cannot consume'),
		'replace': ('values=new int[4];', 'cannot rebind or replace its active sequence'),
		'exchange': ('var other=new int[1];swap(values,other);', 'cannot exchange its active sequence'),
	}
	for name, (body, diagnostic) in negative.items():
		path = out/(name+'.astra')
		path.write_text('int main(){var values=new int[2];foreach(var value in values){'+body+'}return 0;}\n')
		for mode in ['--check', '--dump-core']:
			run([compiler, mode, path], expected=1, diagnostic=diagnostic)
		product = out/name
		run([compiler, path, '-o', product], expected=1, diagnostic=diagnostic)
		assert not product.exists()
	for name, source, diagnostic in [
		('binding-scope', 'int main(){int[1] values={1};foreach(var value in values){}return value;}', "unknown name 'value'"),
		('released-source', 'int main(){var values=new int[2];release values;foreach(var value in values){}return 0;}', 'owned'),
		('source-alias-owner', 'void scan(borrowed int[] view,owned int[] owner){foreach(var value in view){owner=new int[3];}}int main(){var values=new int[2];scan(values,move values);return 0;}', 'borrow'),
	]:
		path = out/(name+'.astra')
		path.write_text(source+'\n')
		run([compiler, path, '-o', out/name], expected=1, diagnostic=diagnostic)
	iterator = 'class Sequence{int index;init(){this.index=0;}bool advance(){this.index=this.index+1;return this.index<4;}int current(){return this.index;}} '
	for name, body, diagnostic in [
		('iterator-move', 'var next=move sequence;', 'cannot consume'),
		('iterator-release', 'release sequence;', 'active receiver or foreach collection'),
		('iterator-alias', 'var alias=sequence;', 'persistent alias'),
	]:
		path = out/(name+'.astra')
		path.write_text(iterator+'int main(){var sequence=new Sequence();foreach(var value in sequence){'+body+'}return 0;}\n')
		run([compiler, path, '-o', out/name], expected=1, diagnostic=diagnostic)
	for name, source, diagnostic in [
		('owning-current', 'class Item{init(){}} class Sequence{init(){}bool advance(){return true;}owned Item current(){var item=new Item();return move item;}}int main(){var sequence=new Sequence();foreach(var item in sequence){}return 0;}', 'copyable current()'),
		('wrong-advance', 'class Sequence{init(){}int advance(){return 1;}int current(){return 0;}}int main(){var sequence=new Sequence();foreach(var item in sequence){}return 0;}', 'bool advance()'),
		('missing-current', 'class Sequence{init(){}bool advance(){return false;}}int main(){var sequence=new Sequence();foreach(var item in sequence){}return 0;}', 'copyable current()'),
	]:
		path = out/(name+'.astra')
		path.write_text(source+'\n')
		run([compiler, path, '-o', out/name], expected=1, diagnostic=diagnostic)
	text = (HERE/'container-iteration.astra').read_text()
	for name, old, new, diagnostic, extra in [
		('container-reserve', 'if (point.x == 3)', 'bool changed = points.reserve(20); if (point.x == 3)', 'overlaps', ''),
		('container-take', 'if (point.x == 3)', 'var removed = points.take(0); if (point.x == 3)', 'overlaps', ''),
		('container-replace', 'if (point.x == 3)', 'points.replace(0, point); if (point.x == 3)', 'overlaps', ''),
		('container-release', 'if (point.x == 3)', 'release points; if (point.x == 3)', 'active receiver or foreach collection', ''),
		('container-alias', 'usability_event(inspect(entry));', 'var alias = entry;', 'call-scoped readonly', ''),
		('container-resource-escape', 'if (present(handle))', 'var escaped = handle; if (present(handle))', 'call-scoped readonly', ''),
		('container-mutable-inspector', 'return entry.value;', 'entry.value = 0; return entry.value;', 'readonly scoped inspector', ''),
		('container-helper-effect', 'if (point.x == 3)', 'change(points); if (point.x == 3)', 'overlaps', '\nvoid change(Vector<Point> values) { bool changed = values.reserve(99); }\n'),
	]:
		path = out/(name+'.astra')
		path.write_text(text.replace(old, new, 1)+extra)
		for stage in ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, '--vapi', ROOT/'tests/own-field/fixtures/resources.vapi',
				path, HERE/'iterator-source.astra', ROOT/'lib/astra/collections/vector.astra',
				ROOT/'lib/astra/base/errors.astra'], expected=1, diagnostic=diagnostic)
	print(f"{len(receipt['checks'])} sequence checks; receipts: {out}")


if __name__ == '__main__':
	main(*sys.argv[1:])
