#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Nested backing conservation plus actual source cancellation through ancestry."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, prefix, output):
	e = Evidence(compiler, output, 'runtime-composition-17-context-nesting')
	here = Path(__file__).resolve().parent
	sources = [here / 'context-nesting.c', here / 'context-provider.c', ROOT / 'lib/runtime/runtime/context-17.c']
	e.files(*sources, here / 'context-provider.h', ROOT / 'lib/runtime/runtime/context-17.h', here / 'cancel-source.py', Path(__file__))
	flags = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-g']
	expected = 'nested contexts: actual parent backing, closed-anchor ancestry leases, worker final release, refusal conservation and bounded acyclic disposal\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('nesting-' + level)
		e.run(['cc', *flags, '-' + level, *sources, '-o', product])
		e.run([product], stdout=expected, timeout=20)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'nesting-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	for sanitizer in ['address,undefined', 'thread']:
		product = e.output / ('nesting-' + sanitizer.replace(',', '-'))
		e.run(['clang', *flags, '-O1', '-fsanitize=' + sanitizer, *sources, '-o', product])
		e.run([product], stdout=expected, timeout=30, env={'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1', 'UBSAN_OPTIONS': 'halt_on_error=1', 'TSAN_OPTIONS': 'halt_on_error=1'})
		e.files(product)
	e.run([sys.executable, here / 'cancel-source.py', e.compiler, prefix, e.output / 'source', 'nested'], stdout='PASS: runtime-composition-17-source-cancellation-nested: 46 commands\n', timeout=240)
	e.files(e.output / 'source/runtime-composition-17-source-cancellation-nested.json')
	# The typed parent boundary refuses an affine handle at semantic analysis;
	# the runtime controls above independently refuse capability laundering.
	negative = e.output / 'affine-parent.astra'
	negative.write_text('int main(){var parent=affine_allocator(1,8192,7,64);var child=nested_allocator(parent,1,4099,3,64);return 0;}')
	e.run([e.compiler, '-c', negative, '--vapi', ROOT / 'lib/bindings/memory/contexts.vapi', '-o', e.output / 'negative.o'], expected=1, contains='ConcurrentAllocator')
	e.files(negative)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
