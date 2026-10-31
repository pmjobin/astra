# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise opaque task libraries with the separately linked Linux provider."""
from pathlib import Path
import hashlib
import itertools
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

from units import metadata

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
TRACE = (b'+221\nD2000\n-221\n+222\nD2010\nD2001\nD2000\n-222\n'
	b'+223\nD2010\nD2001\nD2002\nD2000\n-223\nD2011\n'
	b'+224\nD2010\nD2001\nD2000\n-224\n+225\nD2010\nD2001\nD2002\nD2000\n-225\nD2011\n')


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main(compiler_path, uring_path, output_path):
	compiler = Path(compiler_path).resolve(strict=True)
	uring = Path(uring_path).resolve(strict=True) / 'lib/liburing.a'
	output = Path(output_path).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='linux-task-units-', dir=output))
	api = ROOT / 'tests/own-field/fixtures/resources.vapi'
	observer_source = ROOT / 'tests/own-field/companion.c'
	fixtures = [HERE / ('unit-task-' + role + '.astra') for role in ['provider', 'middle', 'client']]
	runtimes = [compiler.parent / 'lib/astra/async-virtual.o',
		compiler.parent / 'lib/astra/libastra-async-linux.a', uring]
	sources = [Path(__file__).resolve(), HERE / 'units.py', api, observer_source, *fixtures,
		*[ROOT / ('lib/astra/async/' + name) for name in ['virtual.c', 'virtual.h', 'linux.c', 'linux.h', 'provider.h']]]
	receipt = dict(format='astra-m15-linux-task-units/1', compiler_sha256=sha(compiler),
		sources={str(p.relative_to(ROOT)): sha(p) for p in sources},
		runtimes={str(p): sha(p) for p in runtimes}, checks=[], products={}, generated={})

	def save():
		(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	def product(path):
		receipt['products'][str(path)] = sha(path)

	def run(argv, stdout=b'', memory=False, timed=False):
		argv = list(map(str, argv))
		started = time.perf_counter()
		x = subprocess.run(argv, cwd=out, capture_output=True, timeout=90,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', DEBUGINFOD_URLS=''))
		elapsed = time.perf_counter() - started
		passed = x.returncode == 0 and (stdout is None or x.stdout == stdout)
		passed &= all(part in x.stderr for part in [b'ERROR SUMMARY: 0 errors',
			b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)']) if memory else not x.stderr
		if timed:
			passed &= elapsed >= 0.25  # Three independently completed 100-ms timers.
		receipt['checks'].append(dict(argv=argv, exit=x.returncode, elapsed_seconds=elapsed,
			stdout=x.stdout.decode(errors='replace'), stderr=x.stderr.decode(errors='replace'), passed=bool(passed)))
		save()
		assert passed, receipt['checks'][-1]
		return x.stdout

	def source(role):
		text = (HERE / ('unit-task-' + role + '.astra')).read_text()
		text = text.replace('VirtualExecutor', 'LinuxExecutor')
		text = text.replace('returns RunStatus;', 'returns RunStatus provider "linux-io-uring";')
		text = text.replace('delay_ticks(5)', 'delay_ms(100)')
		if role == 'client':
			text = text.replace('\t\texecutor.advance(4);\n\t\texecutor.pump(1);\n', '')
		return text

	def provider(directory, role, module, exports, level, imports=()):
		directory.mkdir(exist_ok=True)
		copy = directory / (role + '-implementation.astra')
		copy.write_text(source(role))
		receipt['generated'][str(copy)] = sha(copy)
		interface, obj = directory / (role + '.asti'), directory / (role + '.o')
		run([compiler, '-g', '-O' + str(level), '-c', '--vapi', api, '--module', module,
			*[item for name in exports for item in ['--native-export', module + '.' + name]],
			*[item for path in imports for item in ['--import-module', path]],
			'--emit-interface', interface, copy, '-o', obj])
		assert all('provider=1;' in fields['contract'] for key, fields in metadata(interface.read_text()).items() if key.startswith('task '))
		copy.unlink()
		product(interface)
		product(obj)
		return interface

	observer = out / 'observer.o'
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', observer_source, '-o', observer])
	product(observer)
	leaves = {}
	for level in [0, 1, 2]:
		directory = out / ('leaf-' + str(level))
		provider(directory, 'provider', 'NativeTasks',
			['Error', 'AsyncError', 'Reply<int>', 'Job<int>', 'create', 'compute'], level)
		undefined = run(['nm', '-u', directory / 'provider.o'], stdout=None)
		assert b'astra_async_linux_delay_ms' in undefined
		leaves[level] = directory
	middles = {}
	for leaf, middle in [*itertools.product([0, 2], repeat=2), (1, 1)]:
		directory = out / f'leaf{leaf}-middle{middle}'
		directory.mkdir()
		for path in leaves[leaf].iterdir():
			if path.suffix in ['.asti', '.o']:
				shutil.copyfile(path, directory / path.name)
		provider(directory, 'middle', 'TaskMiddle', ['work'], middle, [directory / 'provider.asti'])
		middles[leaf, middle] = directory
	client = out / 'client.astra'
	client.write_text(source('client'))
	receipt['generated'][str(client)] = sha(client)
	for leaf, middle, level in [*itertools.product([0, 2], repeat=3), (1, 1, 1)]:
		directory = middles[leaf, middle]
		binary = directory / ('client-O' + str(level))
		run([compiler, '-g', '-O' + str(level), '--vapi', api, '--import-module', directory / 'middle.asti',
			client, *[item for path in [*runtimes, observer] for item in ['--link-object', path]], '-o', binary])
		run([binary], stdout=TRACE, timed=True)
		run(['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
			'--errors-for-leak-kinds=all', '--error-exitcode=99', binary], stdout=TRACE, memory=True, timed=True)
		product(binary)
	assert sha(compiler) == receipt['compiler_sha256']
	assert all(sha(ROOT / path) == digest for path, digest in receipt['sources'].items())
	assert all(sha(Path(path)) == digest for path, digest in receipt['runtimes'].items())
	assert all(sha(Path(path)) == digest for path, digest in receipt['products'].items())
	receipt['all_passed'] = True
	save()
	print(out / 'checks.json')


if __name__ == '__main__':
	main(*sys.argv[1:])
