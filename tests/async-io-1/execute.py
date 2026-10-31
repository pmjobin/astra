# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Finite real generated-program and explicitly injected deferred-error controls."""
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

SOURCE = Path(__file__).resolve().parents[2]

def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
	compiler, prefix, output = [Path(value).resolve() for value in sys.argv[1:4]]
	output.mkdir(parents=True, exist_ok=True)
	receipt = output / 'receipts.json'
	if receipt.exists():
		history = output / 'history'
		history.mkdir(exist_ok=True)
		(history / (sha(receipt) + '.json')).write_bytes(receipt.read_bytes())
	records = []
	identity = {'compiler_sha256': sha(compiler), 'library_sha256': sha(prefix / 'lib/liburing.a'), 'source_sha256': {str(p.relative_to(SOURCE)): sha(p) for p in (SOURCE / 'tests/async-io-1').rglob('*') if p.is_file()}, 'records': records}
	def save():
		receipt.write_text(json.dumps(identity, separators=(',', ':')) + '\n')
	def run(name, command, expected=0, product=None):
		command = list(map(str, command))
		result = subprocess.run(command, capture_output=True, timeout=90)
		row = {'name': name, 'command': command, 'expected': expected, 'exit': result.returncode, 'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(), 'stderr_sha256': hashlib.sha256(result.stderr).hexdigest(), 'stdout_bytes': len(result.stdout), 'stderr_bytes': len(result.stderr), 'status': 'PASS' if result.returncode == expected else 'FAIL'}
		if product is not None and result.returncode == expected:
			product.write_bytes(result.stdout)
			row['product_sha256'] = sha(product)
		if len(result.stdout) < 2000:
			row['observations'] = result.stdout.decode(errors='replace')
		if row['status'] == 'FAIL':
			row['diagnostic'] = result.stderr.decode(errors='replace')[-5000:]
		records.append(row)
		save()
		print(name, row['status'], flush=True)
		assert row['status'] == 'PASS', (command, result.returncode, result.stdout[-2000:], result.stderr[-5000:])
		return result.stdout
	common = ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-I' + str(prefix / 'include'), '-I' + str(SOURCE / 'lib/runtime/async')]
	core = output / 'core.o'
	provider = output / 'linux.o'
	run('shared-core-build', common + ['-c', SOURCE / 'lib/runtime/async/virtual.c', '-o', core])
	run('observed-provider-build', common + ['-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', '-c', SOURCE / 'lib/runtime/async/linux.c', '-o', provider])
	support = [SOURCE / 'lib/astra/base/errors.astra', SOURCE / 'lib/astra/async/linux.astra']
	app = [SOURCE / 'tests/async-io-1/application' / n for n in ('types.astra', 'produce.astra', 'controller.astra', 'main.astra')]
	plain = output / 'plain-observer.o'
	run('plain-observer-build', common + ['-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', '-DASTRA_LINUX_PLAIN_OBSERVER', '-c', SOURCE / 'tests/async-io-1/observer.c', '-o', plain])
	objects = [core, provider, prefix / 'lib/liburing.a']
	def cli(name, sources, observer, extra=()):
		program = output / 'program'
		args = [compiler, *support, *sources, *extra]
		for obj in [*objects, observer]:
			args += ['--link-object', obj]
		run(name + '-CLI-build', [*args, '-o', program])
		run(name + '-REAL-execute', [program], 42)
	cli('four-source', app, plain)
	llvm = output / 'program.ll'
	run('Astra-verified-LLVM', [compiler, '--dump-llvm', *support, *app], product=llvm)
	observer = output / 'observer.o'
	run('allocation-observer-build', common + ['-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', '-c', SOURCE / 'tests/async-io-1/observer.c', '-o', observer])
	for name in ('O0', 'O2', 'O2-FMA', 'preserved-O2'):
		input_llvm, optimized = output / 'input.ll', output / 'optimized.ll'
		text = llvm.read_text()
		if name == 'preserved-O2':
			text = re.sub(r'^(define (?:internal )?(?:fastcc )?[^\n]+) \{$', r'\1 noinline {', text, flags=re.M)
		input_llvm.write_text(text)
		run(name + '-input-verify', ['opt', '-passes=verify', '-disable-output', input_llvm])
		run(name + '-optimize', ['opt', '-passes=verify' if name == 'O0' else '-passes=default<O2>', '-S', input_llvm, '-o', optimized])
		run(name + '-output-verify', ['opt', '-passes=verify', '-disable-output', optimized])
		obj = output / 'program.o'
		program = output / 'observed-program'
		run(name + '-LLVM-object', ['llc', '-O0' if name == 'O0' else '-O2', *(['-mattr=+fma'] if name == 'O2-FMA' else []), '-filetype=obj', optimized, '-o', obj])
		run(name + '-observed-link', common + [obj, *objects, observer, SOURCE / 'tests/async-io-1/entry.c', '-Wl,--wrap=malloc,--wrap=calloc,--wrap=free,--wrap=astra_async_new,--wrap=astra_async_linux_delay_ms,--wrap=astra_async_release_wait,--wrap=astra_async_complete,--wrap=io_uring_submit_and_wait', '-o', program])
		run(name + '-REAL-allocation-retirement', [program], 42)
	for name in ('cancellation', 'manual', 'resource'):
		observer = output / (name + '-observer.o')
		run(name + '-observer-build', common + ['-c', SOURCE / ('tests/async-io-1/' + name + '-observer.c'), '-o', observer])
		extra = ['--vapi', SOURCE / 'tests/async-io-1/resource.vapi'] if name == 'resource' else []
		cli(name, [SOURCE / ('tests/async-io-1/' + name + '.astra')], observer, extra)
	run('deferred-Astra-verified-LLVM', [compiler, '--dump-llvm', *support, SOURCE / 'tests/async-io-1/deferred.astra'], product=llvm)
	obj = output / 'program.o'
	observer = output / 'deferred-observer.o'
	program = output / 'deferred-program'
	run('deferred-LLVM-object', ['llc', '-filetype=obj', llvm, '-o', obj])
	run('deferred-observer-build', common + ['-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', '-c', SOURCE / 'tests/async-io-1/deferred-observer.c', '-o', observer])
	run('deferred-injected-link', common + [obj, *objects, observer, SOURCE / 'tests/async-io-1/entry.c', '-Wl,--wrap=astra_async_linux_open,--wrap=astra_async_linux_delay_ms', '-o', program])
	run('INJECTED-EIO-generated-catch', [program], 42)
	run('startup-Astra-verified-LLVM', [compiler, '--dump-llvm', *support, SOURCE / 'tests/async-io-1/startup.astra'], product=llvm)
	run('startup-LLVM-object', ['llc', '-filetype=obj', llvm, '-o', obj])
	run('startup-observer-build', common + ['-c', SOURCE / 'tests/async-io-1/startup-observer.c', '-o', observer])
	run('startup-injected-link', common + [obj, *objects, observer, SOURCE / 'tests/async-io-1/entry.c', '-Wl,--wrap=io_uring_queue_init_params', '-o', program])
	run('INJECTED-EPERM-generated-catch', [program], 42)
	run('duration-Astra-verified-LLVM', [compiler, '--dump-llvm', *support, SOURCE / 'tests/async-io-1/duration.astra'], product=llvm)
	run('duration-LLVM-object', ['llc', '-filetype=obj', llvm, '-o', obj])
	run('duration-observer-build', common + ['-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', '-c', SOURCE / 'tests/async-io-1/duration-observer.c', '-o', observer])
	run('duration-injected-link', common + [obj, *objects, observer, SOURCE / 'tests/async-io-1/entry.c', '-Wl,--wrap=astra_async_linux_open,--wrap=astra_async_linux_delay_ms', '-o', program])
	run('INJECTED-generated-duration-units', [program], 42)
	identity['status'] = 'PASS'
	save()
	return 0

if __name__ == '__main__':
	sys.exit(main())
