#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Generated endpoint errors and process-local descriptor exhaustion recover."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-endpoint-errors')
	here = Path(__file__).resolve().parent
	sources = [here / 'endpoint-errors.astra', ROOT / 'lib/astra/hosted/network.astra', ROOT / 'lib/astra/base/errors.astra']
	providers = [ROOT / 'lib/runtime/platform/network-posix.c', ROOT / 'lib/runtime/platform/text-posix.c', ROOT / 'lib/runtime/runtime/context-17.c', here / 'endpoint-errors-oracle.c']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	flags = ['-Wl,--wrap=astra_context17_destroy']
	e.files(*sources, *providers, vapi, Path(__file__), ROOT / 'tests/concurrency-runtime-13/sanitizers.py')
	expected = 'endpoint errors: ranges, formats, refusal, oversize, actual EMFILE and recovery; FD/context conservation\n'
	for level in ['0', '1', '2']:
		obj, product = [e.output / ('errors-O' + level + suffix) for suffix in ['.o', '']]
		e.run([e.compiler, '-O' + level, '--entry-object', *sources, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, *flags, '-o', product])
		e.run([product], stdout=expected); e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'errors-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	for sanitizer in ['address', 'thread']:
		instrument(e, 'endpoint-errors', sources, providers, expected, sanitizer, link_flags=flags, vapis=[vapi])
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
