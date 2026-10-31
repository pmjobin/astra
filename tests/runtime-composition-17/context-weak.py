#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A selected intrinsic control allocation outlives strong payload destruction."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-context-weak')
	here = Path(__file__).resolve().parent
	sources = [here / 'context-weak-race.astra']
	providers = [ROOT / 'lib/runtime/runtime/threads-13.c', ROOT / 'lib/runtime/runtime/monitors-13.c', ROOT / 'lib/runtime/runtime/context-17.c', here / 'context-provider.c', ROOT / 'tests/concurrency-runtime-13/weak-race-oracle.c']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-custom.vapi']
	imports = [argument for path in vapis for argument in ['--vapi', path]]
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]
		e.files(obj)
	expected = 'weak race: four native workers, one payload destruction, expired upgrade\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('weak-' + level)
		e.run([e.compiler, '-' + level, *sources, *imports, *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected, timeout=30)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'weak-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=90)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'weak', sources, providers, expected, sanitizer, vapis=vapis)
		# Atomic control counts do not grant the allocator a threading capability.
	template = sources[0].read_text()
	for name, text in [
		('affine', template.replace('owned-concurrent', 'owned-affine')
		.replace('ConcurrentAllocator', 'AffineAllocator')
		.replace('custom_allocator(16387, 17)', 'affine_allocator(1, 16387, 17, 64)')),
		('static', template.replace('[Allocator(kind="context",context="owned-concurrent")]',
		'[Allocator(kind="region",domain="m17_weak_static",capacity="16387",blocks="17")]')
		.replace('new (context) Tile(17)', 'new Tile(17)'))]:
		negative = e.output / ('weak-' + name + '-capture.astra')
		negative.write_text(text)
		e.run([e.compiler, '-c', negative, *imports, '-o', negative.with_suffix('.o')], expected=1,
			contains='thread')
		e.files(negative)
	e.files(*sources, *providers, *vapis, ROOT / 'lib/runtime/runtime/context-17.h', here / 'context-provider.h', Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
