# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Explicit nonnull composition without changing reference or ABI defaults."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main(compiler_path, output_path):
	compiler, output = Path(compiler_path).resolve(), Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='nonnull-', dir=output))
	sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
	source = HERE/'nonnull-general.astra'
	async_source = HERE/'nonnull-general-async.astra'
	projection_source = HERE/'nonnull-projection.astra'
	vector = ROOT/'lib/astra/collections/vector.astra'
	errors = ROOT/'lib/astra/base/errors.astra'
	virtual = ROOT/'lib/astra/async/virtual.astra'
	provider = compiler.parent/'lib/astra/async-virtual.o'
	receipt = dict(compiler=str(compiler), compiler_sha256=sha(compiler),
		sources={str(path.relative_to(ROOT)): sha(path) for path in [source, async_source, projection_source, vector, errors, virtual, Path(__file__).resolve()]},
		async_provider_sha256=sha(provider), checks=[], products={})

	def run(argv, expected=0, diagnostic=None, memory=False, stdout=b''):
		argv = list(map(str, argv))
		result = subprocess.run(argv, cwd=ROOT, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == expected and (stdout is None or result.stdout == stdout)
		if diagnostic:
			passed &= diagnostic.encode() in result.stderr
			passed &= all(text not in result.stderr for text in [b'internal ', b'assertion', b'CRITICAL'])
		elif memory:
			passed &= all(text in result.stderr for text in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		else:
			passed &= not result.stderr
		receipt['checks'].append(dict(command=argv, expected_exit=expected, actual_exit=result.returncode,
			stdout=result.stdout.decode(errors='replace'), stderr=result.stderr.decode(errors='replace'), passed=bool(passed),
			astra_inputs={arg: sha(Path(arg)) for arg in argv if arg.endswith('.astra') and Path(arg).is_file()}))
		(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
		assert passed, receipt['checks'][-1]
		return result.stdout

	for fixture, dependencies, links in [(source, [vector], []), (async_source, [vector, errors, virtual], ['--link-object', provider]), (projection_source, [vector, errors, virtual], ['--link-object', provider])]:
		for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, *dependencies, fixture], stdout=None)
		for level in ['-O0', '-O1', '-O2']:
			executable = out/(fixture.stem+level)
			run([compiler, level, *dependencies, fixture, *links, '-o', executable])
			receipt['products'][str(executable)] = sha(executable)
			run([executable])
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
				'--errors-for-leak-kinds=all', '--error-exitcode=99', executable], memory=True)
		peer = out/(fixture.stem+'-abi-peer.astra')
		for stage in ['--dump-nabi', '--dump-cabi', '--dump-llvm']:
			peer.write_text(fixture.read_text())
			qualified = run([compiler, stage, *dependencies, peer], stdout=None)
			# Keep one file identity and exact byte positions. Error text contains
			# no keyword, so only explicit source contracts are removed.
			peer.write_text(fixture.read_text().replace('nonnull ', '        '))
			ordinary = run([compiler, stage, *dependencies, peer], stdout=None)
			if stage == '--dump-nabi' and links:
				# Native frames retain SSA instruction positions, including erased
				# proof obligations. Physical field identities/layouts stay exact.
				qualified = re.sub(rb'position=[0-9]+', b'position=SOURCE', qualified)
				ordinary = re.sub(rb'position=[0-9]+', b'position=SOURCE', ordinary)
			assert qualified == ordinary, f'{fixture.name} {stage}: nonnull changed physical ABI or execution'

	text = source.read_text()
	for name, old, new, diagnostic in [
		('generic-null', 'return count(values) +', 'return count(null) +', 'current non-null proof'),
		('interface-null', 'apply(transform, 10)', 'apply(null, 10)', 'current non-null proof'),
		('callable-unproved', 'int apply_function(nonnull Fn<int,int> function, int value) { return function(value); }', 'int apply_function(nonnull Fn<int,int> function, int value) { return function(value); } int unproved(Fn<int,int> function) { return apply_function(function, 7); }', 'current non-null proof'),
		('generic-unproved', 'if (values == null || transform == null)', 'if (false || transform == null)', 'current non-null proof'),
		('generic-property-unproved', 'owned nonnull Vector<Point> values;', 'owned Vector<Point> values;', 'current non-null proof'),
		('callable-forgery', 'return increment;', 'return 0;', 'expected return value of type'),
	]:
		invalid = out/(name+'.astra'); invalid.write_text(text.replace(old, new, 1))
		assert invalid.read_text() != text, name
		for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, vector, invalid], expected=1, diagnostic=diagnostic)
	invalid = out/'moved-across-delay.astra'
	invalid.write_text(async_source.read_text().replace('count(moved.view)', 'count(repository.view)'))
	# The Core dump precedes CFG owner-liveness validation.
	for stage in ['--check', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, vector, errors, virtual, invalid], expected=1, diagnostic='moved')
	projection = projection_source.read_text()
	for name, old, new in [
		('stale-property-effect', 'repository.clear();\n\t\tif (repository.item != null) { return inspect_projection(repository.item); }', 'repository.clear(); return inspect_projection(repository.item);'),
		('stale-property-suspension', 'if (repository.item != null) {\n\t\t\tif (inspect_projection(repository.item)', 'if (true) {\n\t\t\tif (inspect_projection(repository.item)'),
	]:
		invalid = out/(name+'.astra'); invalid.write_text(projection.replace(old, new, 1)); assert invalid.read_text() != projection
		for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
			run([compiler, stage, vector, errors, virtual, invalid], expected=1, diagnostic='current non-null proof')
	invalid = out/'wrong-property-receiver.astra'
	invalid.write_text(projection+'\nint wrong_receiver(OptionalRepository first, OptionalRepository second) { if (first.item != null) { return inspect_projection(second.item); } return -1; }\n')
	for stage in ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']:
		run([compiler, stage, vector, errors, virtual, invalid], expected=1, diagnostic='current non-null proof')
	receipt['status'] = 'PASS' 
	(out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(f'PASS {len(receipt["checks"])} public nonnull commands; receipt {out / "checks.json"}')


if __name__ == '__main__':
	main(*sys.argv[1:])
