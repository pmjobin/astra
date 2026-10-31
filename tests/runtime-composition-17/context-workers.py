#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real transitive context transfers to native worker frames (default frame backing)."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-context-workers')
	here = Path(__file__).resolve().parent
	sources = [here / 'context-workers.astra', ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/threaded.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'context-provider.c', here / 'context-worker-oracle.c']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-custom.vapi']
	imports = [part for path in vapis for part in ['--vapi', path]]
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]
		e.files(obj)
	expected = 'context workers: two overlapping native threads, exact allocator origins, joined custom backing retirement\n'
	# Independent calculation of the declared integer recurrence.
	for identity in [1, 2]:
		value = identity
		for i in range(50003): value = (value * 17 + i % 251) % 65521
		e.data.setdefault('reference_results', []).append(value)
	e.save()
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('workers-' + level)
		e.run([e.compiler, '-' + level, *sources, *imports, *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'workers-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'workers', sources, providers, expected, sanitizer, vapis=vapis)
	negative = e.output / 'affine-nested-capture.astra'
	negative.write_text('''class AffineHolder {
	private owned AffineAllocator context;
	init(owned AffineAllocator context) { this.context = move context; }
}
async void bad(owned AffineHolder holder) {}
int main() { return 0; }
''')
	e.run([e.compiler, '-c', negative, *sources[1:], '--vapi', vapis[0], '-o', e.output / 'affine-nested-capture.o'], expected=1)
	e.files(negative, here / 'thread-inventory-probe.c', here / 'join-retirement-probe.c')
	e.files(*sources, *providers, *vapis, ROOT / 'lib/runtime/runtime/context-17.h', here / 'context-provider.h', Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
