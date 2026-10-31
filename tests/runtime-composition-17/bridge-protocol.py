#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real common-core/worker/io_uring protocol supplement, with race tools."""
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, prefix, output):
	e = Evidence(compiler, output, 'runtime-composition-17-bridge-protocol')
	prefix = Path(prefix).resolve()
	here = Path(__file__).resolve().parent
	sources = [here / 'bridge-protocol.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/async/linux.c']
	flags = ['-std=c11', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', '-isystem', prefix / 'include']
	expected = 'bridge protocol: two worker instances, actual file CQEs, success/error/foreign cancellation, exact retirement and joined shutdown\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('protocol-' + level)
		e.run(['cc', '-' + level, *flags, *sources, prefix / 'lib/liburing.a', '-o', product])
		e.run([product, e.output / 'payload'], stdout=expected, timeout=15)
		e.files(product)
	product = e.output / 'protocol-O2'
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product, e.output / 'payload'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	for sanitizer in ['address,undefined', 'thread']:
		observed = e.output / ('protocol-' + sanitizer.replace(',', '-'))
		e.run(['clang', '-O1', *flags, '-fsanitize=' + sanitizer, *sources, prefix / 'lib/liburing.a', '-o', observed])
		e.run([observed, e.output / 'payload'], stdout=expected, timeout=45, env={'TSAN_OPTIONS': 'halt_on_error=1', 'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1', 'UBSAN_OPTIONS': 'halt_on_error=1'})
		e.files(observed)
	symbols = e.run(['nm', '--defined-only', product]).stdout
	for name in ['astra_async_new', 'astra_async_start', 'astra_async_bridge_start', 'astra_async_bridge_wait', 'astra_async_threaded_open', 'astra_async_virtual_open', 'astra_async_linux_open']:
		assert len(re.findall(r'^[0-9a-f]+ T ' + name + r'$', symbols, re.M)) == 1, name
	trace = e.output / 'kernel.strace'
	e.run(['strace', '-f', '-o', trace, '-e', 'trace=io_uring_setup,io_uring_enter,io_uring_register,eventfd2,poll,read,write,clone,clone3', product, e.output / 'payload'], stdout=expected, timeout=15)
	text = trace.read_text()
	for operation in ['IORING_SETUP_SINGLE_ISSUER', 'IORING_SETUP_CQSIZE', 'IORING_SETUP_NO_SQARRAY', 'eventfd2(', 'io_uring_enter(', 'poll(']: assert operation in text, operation
	assert 'poll(' in text and 'POLLIN' in text
	e.files(*sources, prefix / 'lib/liburing.a', trace, Path(__file__))
	for name in ['virtual.h', 'provider.h', 'linux.h', 'task-core17.c', 'task-api17.c', 'worker17.c']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
