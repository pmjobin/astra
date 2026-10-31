# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Recoverable threaded pool construction failures, including partial startup."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-pool-failures')
	here = Path(__file__).parent
	astra = [here / 'pool-failures.astra', ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra']
	providers = [ROOT / 'lib/runtime/async/threaded.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'pool-failures-oracle.c']
	flags = ['-Wl,--wrap=' + name for name in ['calloc', 'free', 'pthread_create']]
	entry = e.output / 'entry.c'
	entry.write_text('extern int run_pool_failures(void);int main(void){return run_pool_failures();}\n')
	expected = 'pool failures: two invalid counts, three allocation faults, two worker-start faults, five recovered runs, exact retirement\n'
	for level in ['O0', 'O1', 'O2']:
		obj = e.output / (level + '.o'); product = e.output / level
		e.run([e.compiler, '-' + level, '-c', *astra, '-o', obj])
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, entry, *flags, '-o', product])
		e.run([product], stdout=expected, timeout=20)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'pool-failures', astra, providers, expected, sanitizer, flags)
	e.files(*astra, *providers, Path(__file__), entry, ROOT / 'lib/runtime/async/virtual.c')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
