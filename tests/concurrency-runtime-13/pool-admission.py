# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe the threaded provider's bounded private ABI admission and full drain."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-pool-admission')
	here = Path(__file__).parent
	runtime = ROOT / 'lib/runtime/async/threaded.c'
	source = here / 'pool-admission.c'
	expected = 'pool runtime supplement: 256 registrations, capacity/root/association/cold/closed refusal, stale tokens, 260 exact retirements\n'
	for sanitizer in [None, 'address,undefined', 'thread']:
		product = e.output / (sanitizer or 'plain')
		flags = ['-fsanitize=' + sanitizer] if sanitizer else []
		e.run(['clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *flags, runtime, source, '-o', product])
		e.run([product], stdout=expected, timeout=20)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'plain'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
	e.files(runtime, runtime.parent / 'virtual.c', runtime.with_name('virtual.h'), source, Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
