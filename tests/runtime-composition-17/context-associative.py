#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Selected Map/Cache backing, replacement and escaping custom-backed entries."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-context-associative')
	here = Path(__file__).resolve().parent
	sources = [here / 'context-associative.astra', ROOT / 'lib/astra/collections/context-map.astra', ROOT / 'lib/astra/collections/context-cache.astra']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'context-provider.c']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-custom.vapi']
	imports = [argument for path in vapis for argument in ['--vapi', path]]
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]
		e.files(obj)
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('associative-' + level)
		e.run([e.compiler, '-' + level, *sources, *imports, *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout='', timeout=15)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'associative-O2'], stdout='', contains='ERROR SUMMARY: 0 errors', timeout=45)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'associative', sources, providers, '', sanitizer, vapis=vapis)
	for name, replacement, diagnostic in [
		('unselected', ('new (context) ContextMapEntry', 'new ContextMapEntry'), 'explicit instance'),
		('affine', ('borrowed ConcurrentAllocator context', 'borrowed AffineAllocator context'), 'lifetime/thread contract')]:
		negative = e.output / ('generic-' + name + '.astra')
		negative.write_text(sources[1].read_text().replace(*replacement))
		e.run([e.compiler, '-c', sources[0], negative, sources[2], *imports,
			'-o', negative.with_suffix('.o')], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(*sources, *providers, *vapis, ROOT / 'lib/runtime/runtime/context-17.h', here / 'context-provider.h', Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
