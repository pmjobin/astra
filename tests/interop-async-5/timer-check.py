#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh unchanged ASYNC-IO-1 timer controls using the selected private provider.

Builds explicit out-of-source C products and invokes the original execute.py.
It neither reconfigures Meson nor changes the default linux_async option.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import resource
import shlex
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
OLD = ROOT / 'tests/async-io-1'
ASYNC = ROOT / 'lib/runtime/async'


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	compiler, output = [Path(value).resolve() for value in sys.argv[1:3]]
	prefix = Path(sys.argv[3] if len(sys.argv) > 3 else os.environ.get(
		'ASTRA_LIBURING_PREFIX', Path.home() / '.local/opt/liburing-2.15')).resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	archive = prefix / 'lib/liburing.a'
	header = prefix / 'include/liburing/io_uring_version.h'
	fixture_paths = sorted(p for p in OLD.rglob('*') if p.is_file())
	sources = [Path(__file__).resolve(), *fixture_paths,
		*[ASYNC / name for name in ['virtual.c', 'virtual.h', 'provider.h', 'linux.c', 'linux.h']],
		ROOT / 'lib/astra/base/errors.astra', ROOT / 'lib/astra/async/linux.astra']
	receipt = dict(status='RUNNING', compiler_sha256=sha(compiler), prefix=str(prefix),
		sources={str(path.relative_to(ROOT)): sha(path) for path in sources},
		commands=[], products={}, real_profile=None, valgrind=0)

	def save():
		(output / 'results.json').write_text(json.dumps(receipt, indent=2) + '\n')

	def blocked(reason):
		receipt.update(status='ENVIRONMENT_BLOCKED', reason=reason)
		save()
		print('ENVIRONMENT_BLOCKED timer regression:', reason)
		return 77

	if not archive.is_file() or not header.is_file():
		return blocked('existing matching private liburing headers/static archive missing')
	version = header.read_text()
	major = int(re.search(r'^#define IO_URING_VERSION_MAJOR (\d+)$', version, re.M)[1])
	minor = int(re.search(r'^#define IO_URING_VERSION_MINOR (\d+)$', version, re.M)[1])
	if (major, minor) < (2, 15):
		return blocked('selected liburing headers are older than 2.15')
	receipt['liburing'] = dict(archive=str(archive), archive_sha256=sha(archive),
		header_version=[major, minor],
		headers={str(p.relative_to(prefix)): sha(p)
		for p in sorted((prefix / 'include').rglob('*.h'))})
	options = compiler.parent / 'meson-info/intro-buildoptions.json'
	if options.is_file():
		build_options = json.loads(options.read_text())
		receipt['default_linux_async'] = next(row['value'] for row in build_options if row['name'] == 'linux_async')
		assert receipt['default_linux_async'] is False, 'timer recipe expects the preserved default linux_async=false build'
	save()

	def run(name, command, expected=0, memory=False, kind='real'):
		command = list(map(str, command))
		started = time.monotonic()
		result = subprocess.run(command, cwd=output, capture_output=True, timeout=300,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		good = result.returncode == expected
		if memory:
			good &= all(part in result.stderr for part in [b'ERROR SUMMARY: 0 errors',
				b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'])
		row = dict(name=name, kind=kind, command=command, exit=result.returncode,
			expected=expected, passed=bool(good), seconds=round(time.monotonic()-started, 6),
			stdout_sha256=hashlib.sha256(result.stdout).hexdigest(),
			stderr_sha256=hashlib.sha256(result.stderr).hexdigest(),
			stdout=result.stdout.decode(errors='replace')[-16000:],
			stderr=result.stderr.decode(errors='replace')[-8000:])
		receipt['commands'].append(row)
		if not good:
			receipt.update(status='ENVIRONMENT_BLOCKED' if result.returncode == 77 else 'ENGINEERING_FAILED',
				reason=name + ' did not satisfy its explicit expected result')
		if memory and good:
			receipt['valgrind'] += 1
		save()
		print(name, 'PASS' if good else receipt['status'], flush=True)
		if result.returncode == 77:
			raise SystemExit(77)
		assert good, row
		return result

	cc = shlex.split(os.environ.get('CC', 'cc'))
	assert cc
	receipt['c_compiler'] = dict(command=cc, path=shutil.which(cc[0]))
	compiler_version = run('C-compiler-identity', [*cc, '--version'], kind='toolchain')
	receipt['c_compiler']['version'] = compiler_version.stdout.decode().splitlines()[0]
	for tool in ['opt', 'llc', 'valgrind']:
		found = shutil.which(tool)
		if found:
			resolved = Path(found).resolve()
			receipt.setdefault('tool_identities', {})[tool] = dict(path=found, resolved=str(resolved), sha256=sha(resolved))
	common = [*cc, '-std=c11', '-g', '-O2', '-Wall', '-Wextra', '-Werror',
		'-I' + str(prefix / 'include'), '-I' + str(ASYNC)]
	runtime_sources = [ASYNC / 'virtual.c', ASYNC / 'linux.c']
	fixtures = [
		('profile', OLD / 'profile-probe.c', [], [], 'real-kernel-profile'),
		('runtime', OLD / 'runtime-tests.c', [], runtime_sources, 'real-expiry-cancel-pressure'),
		('injected', OLD / 'injected-tests.c', ['-DASTRA_ASYNC_LINUX_TEST_PROTOCOL'], runtime_sources, 'injected-protocol-controls'),
		('cleanup', OLD / 'cleanup-tests.c', ['-DASTRA_ASYNC_LINUX_TEST_PROTOCOL',
		'-Wl,--wrap=io_uring_queue_init_params,--wrap=io_uring_register_probe'], runtime_sources, 'real-cleanup-and-injected-failures'),
	]
	for name, source, flags, dependencies, kind in fixtures:
		program = output / name
		run(name + '-build', [*common, *flags, source, *dependencies, archive, '-o', program], kind='build')
		receipt['products'][name] = sha(program)
		result = run(name + '-execute', [program], kind=kind)
		if name == 'profile':
			probe = json.loads(result.stdout)
			assert probe['status'] == 'PASS' and probe['observed_target_and_cancel'] is True
			receipt['real_profile'] = probe
		save()
	if shutil.which('valgrind'):
		run('runtime-unsuppressed-Valgrind', ['valgrind', '--default-suppressions=no',
			'--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all',
			'--error-exitcode=97', output / 'runtime'], memory=True, kind='real-runtime-memory')
	else:
		receipt['memory_status'] = 'UNAVAILABLE'
	generated = output / 'generated'
	run('unchanged-generated-timer-recipe', [sys.executable, '-B', OLD / 'execute.py',
		compiler, prefix, generated], kind='real-generated-and-labelled-injected-controls')
	child = generated / 'receipts.json'
	child_receipt = json.loads(child.read_text())
	assert child_receipt['status'] == 'PASS'
	receipt['generated'] = dict(receipt=str(child), sha256=sha(child),
		command_count=len(child_receipt['records']), status=child_receipt['status'])
	assert receipt['liburing']['archive_sha256'] == sha(archive), 'selected archive changed during qualification'
	assert all(sha(ROOT / name) == digest for name, digest in receipt['sources'].items()), 'source changed during qualification'
	receipt['status'] = 'PASS'
	save()
	print('Fresh unchanged timer regression: PASS')
	return 0


if __name__ == '__main__':
	raise SystemExit(main())
