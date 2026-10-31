#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Supplementary custom-provider quota, origin, concurrency and final-lease checks."""
from pathlib import Path
import json
import resource
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	e = Evidence(compiler, output, 'runtime-composition-17-sequence-provider')
	here = Path(__file__).resolve().parent; app = ROOT / 'examples/runtime-composition-17'
	sources = [app / 'sequence-provider.c', ROOT / 'lib/runtime/runtime/context-17.c', here / 'sequence-provider-oracle.c']
	for profile in ['native', 'address', 'thread']:
		product = e.output / ('provider-' + profile)
		flags = [] if profile == 'native' else ['-fsanitize=' + ('address,undefined' if profile == 'address' else 'thread'), '-fno-omit-frame-pointer']
		e.run(['clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *flags, *sources, '-o', product])
		result = e.run([product], contains='sequence arena provider: private quotas, concurrent callbacks, distinct origins and last-lease disposal', env={'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1', 'UBSAN_OPTIONS': 'halt_on_error=1', 'TSAN_OPTIONS': 'halt_on_error=1'})
		counts = json.loads(result.stdout.splitlines()[0]); assert counts['opened'] == counts['disposed'] == 2
		contexts = {row['identity']: row for row in counts['arena_contexts']}
		assert contexts[101]['allocations'] == contexts[101]['releases'] == 1 and contexts[101]['refusals'] == 1
		assert contexts[103]['allocations'] == contexts[103]['releases'] == 2008
		assert all(row['peak_live_bytes'] <= row['arena_bytes'] for row in contexts.values())
		assert contexts[103]['gap_reuses'] > 1000
		if profile == 'native':
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=result.stdout, contains='All heap blocks were freed')
		e.files(product)
	e.files(*sources, app / 'sequence-provider.h', ROOT / 'lib/runtime/runtime/context-17.h', Path(__file__), ROOT / 'tests/systems-dsp-9/support.py')
	e.complete()


if __name__ == '__main__': main(*sys.argv[1:])
