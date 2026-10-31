#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Supplementary custom-provider quota, origin, concurrency and final-lease checks."""
from pathlib import Path
import json
import resource
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from freeze_guard import braid_guard, current_include_flags


def main(compiler, output, profile='regression'):
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	e = Evidence(compiler, output, 'runtime-composition-17-braid-provider')
	here = Path(__file__).resolve().parent; app = Path(__file__).resolve().parent
	sources = [app / 'braid-provider.c', ROOT / 'lib/runtime/runtime/context-17.c', here / 'braid-provider-oracle.c']
	guard = braid_guard(e.compiler, profile)
	guard.bind(e)
	e.data.update(qualification_guard=guard.record(), profile=profile,
		regression_only=profile == 'regression', freeze=4, challenge_complete=False)
	e.save()
	def verify(result):
		counts = json.loads(result.stdout.splitlines()[0]); assert counts['opened'] == counts['disposed'] == 2
		assert counts['guard_bytes_per_allocation'] == 64
		contexts = {row['identity']: row for row in counts['arena_contexts']}
		assert contexts[101]['allocations'] == contexts[101]['releases'] == 1 and contexts[101]['refusals'] == 1
		assert contexts[103]['allocations'] == contexts[103]['releases'] == 2008
		assert contexts[103]['gap_reuses'] > 1000
		for row in contexts.values():
			assert row['peak_live_bytes'] <= row['arena_bytes']
			assert row['peak_reserved_live_bytes'] <= row['buddy_reserved_bytes']
			assert row['buddy_splits'] == row['buddy_coalesces'] and row['buddy_splits'] > 0
	for profile in ['native', 'address', 'thread']:
		product = e.output / ('provider-' + profile)
		flags = [] if profile == 'native' else ['-fsanitize=' + ('address,undefined' if profile == 'address' else 'thread'), '-fno-omit-frame-pointer']
		e.run(['clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *current_include_flags(e.output), *flags, *sources, '-o', product])
		result = e.run([product], contains='braid buddy provider: private quotas, concurrent callbacks, distinct origins and last-lease disposal', env={'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1', 'UBSAN_OPTIONS': 'halt_on_error=1', 'TSAN_OPTIONS': 'halt_on_error=1'})
		verify(result)
		if profile == 'native':
			verify(e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], contains='All heap blocks were freed'))
		e.files(product)
	e.files(*sources, app / 'braid-provider.h', ROOT / 'lib/runtime/runtime/context-17.h', Path(__file__), ROOT / 'tests/systems-dsp-9/support.py')
	guard.check(); e.complete()


if __name__ == '__main__': main(*sys.argv[1:])
