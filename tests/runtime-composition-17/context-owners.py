#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual emitted Astra allocation origin, return and destructor controls."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-context-owners')
	here = Path(__file__).resolve().parent
	provider = ROOT / 'lib/runtime/runtime/context-17.c'
	oracle = here / 'context-owner-oracle.c'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	custom_vapi = here / 'context-custom.vapi'
	custom_provider = here / 'context-provider.c'
	source = here / 'context-owners.astra'
	expected = 'context owners: two runtime instances, borrowed factory, escaping backing, external custom provider, exact five destructors\n'
	objects = []
	for native in [provider, oracle, custom_provider]:
		obj = e.output / (native.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', native, '-o', obj])
		objects += ['--link-object', obj]
		e.files(obj)
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('owners-' + level)
		e.run([e.compiler, '-' + level, source, '--vapi', vapi, '--vapi', custom_vapi, *objects, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'owners-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'owners', [source], [provider, oracle, custom_provider], expected, sanitizer, vapis=[vapi, custom_vapi])
	declaration = '[Allocator(kind="context",context="owned-concurrent")]class Cell{init(){}}\n'
	negatives = [
		('missing-instance', declaration + 'int main(){var cell=new Cell();return 0;}', 'context allocation requires an explicit instance'),
		('wrong-capability', declaration + 'int main(){var context=affine_allocator(1,8197,7,64);var cell=new(context)Cell();return 0;}', 'allocator instance lifetime/thread contract differs'),
		('unselected-class', 'class Cell{init(){}}int main(){var context=concurrent_allocator(1,8197,7,64);var cell=new(context)Cell();return 0;}', 'context allocation requires an explicit instance'),
		('moved-context', declaration + 'int main(){var context=concurrent_allocator(1,8197,7,64);var other=move context;var cell=new(context)Cell();return 0;}', None),
	]
	for name, text, diagnostic in negatives:
		negative = e.output / (name + '.astra')
		negative.write_text(text + '\n')
		e.run([e.compiler, '-c', negative, '--vapi', vapi, '-o', e.output / (name + '.o')], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(source, provider, provider.with_suffix('.h'), oracle, vapi, custom_vapi, custom_provider, custom_provider.with_suffix('.h'), Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
