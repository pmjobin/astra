# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare concrete and renamed equivalents of generic async record results."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main(compiler_path, output_path):
	compiler = Path(compiler_path).resolve(strict=True)
	output = Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='async-record-variants-', dir=output))
	fixture = HERE / 'generic-record-async.astra'
	libraries = [ROOT / 'lib/astra/base/errors.astra', ROOT / 'lib/astra/async/virtual.astra']
	provider = compiler.parent / 'lib/astra/async-virtual.o'
	sources = [Path(__file__).resolve(), fixture, *libraries,
		ROOT / 'lib/runtime/async/virtual.c', ROOT / 'lib/runtime/async/virtual.h', ROOT / 'lib/runtime/async/provider.h']
	receipt = dict(format='astra-m15-async-record-equivalence/1', compiler_sha256=sha(compiler),
		sources={str(p.relative_to(ROOT)): sha(p) for p in sources}, provider_sha256=sha(provider),
		variants={}, checks=[], products={})

	def run(argv, memory=False):
		argv = list(map(str, argv))
		started = time.perf_counter()
		result = subprocess.run(argv, cwd=out, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', DEBUGINFOD_URLS=''))
		passed = result.returncode == 0 and not result.stdout
		passed &= all(part in result.stderr for part in [b'ERROR SUMMARY: 0 errors',
			b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)']) if memory else not result.stderr
		receipt['checks'].append(dict(argv=argv, exit=result.returncode, passed=bool(passed),
			elapsed_seconds=time.perf_counter() - started, stdout=result.stdout.decode(errors='replace'),
			stderr=result.stderr.decode(errors='replace')))
		(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
		assert passed, receipt['checks'][-1]

	original = fixture.read_text()
	concrete = original.replace('struct AsyncPair<A, B> { A value; B detail; }',
		'struct ConcreteReply { int value; AsyncTag detail; }')
	assert concrete != original
	concrete = concrete.replace('AsyncPair<int, AsyncTag>', 'ConcreteReply')
	assert 'AsyncPair' not in concrete
	renamed = original.replace('AsyncPair', 'DifferentReply').replace('AsyncTag', 'DifferentTag')
	renamed = renamed.replace('produce_record', 'calculate_reply').replace('inspect_records', 'verify_replies')
	renamed = renamed.replace('int generation; bool accepted;', 'bool accepted; int generation;')
	renamed = renamed.replace('struct DifferentReply<A, B> { A value; B detail; }',
		'struct DifferentReply<A, B> { B detail; A value; }')
	for name, text in [('concrete', concrete), ('renamed-reordered', renamed)]:
		path = out / (name + '.astra')
		path.write_text(text)
		receipt['variants'][name] = dict(sha256=sha(path), transformation='concrete substitution' if name == 'concrete' else 'rename declarations and reorder both nested record fields')
		for level in [0, 1, 2]:
			binary = out / (name + '-O' + str(level))
			run([compiler, '-g', '-O' + str(level), path, *libraries, '--link-object', provider, '-o', binary])
			run([binary])
			run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
				'--errors-for-leak-kinds=all', '--error-exitcode=99', binary], memory=True)
			receipt['products'][str(binary)] = sha(binary)
	assert sha(compiler) == receipt['compiler_sha256'] and sha(provider) == receipt['provider_sha256']
	assert all(sha(ROOT / path) == digest for path, digest in receipt['sources'].items())
	receipt['all_passed'] = True
	(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(out / 'checks.json')


if __name__ == '__main__':
	main(*sys.argv[1:])
