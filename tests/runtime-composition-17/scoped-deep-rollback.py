#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe nested scoped trees, generic nodes, forwarding and rollback."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-deep-rollback')
	here = Path(__file__).resolve().parent
	source = here / 'scoped-deep-rollback.astra'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'scoped-deep-rollback-oracle.c']
	e.files(source, vapi, *providers, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'lib/runtime/runtime/context-17.h')
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += [obj]
		e.files(obj)
	expected = 'scoped deep rollback: 3 contexts, 34 placements, 28 heap child retirements and 4 prefix failures\n'
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_open_scoped', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'free']]
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('scoped-deep-rollback-' + level)
		obj = product.with_suffix('.o')
		e.run([e.compiler, '-' + level, '-c', source, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-pthread', obj, *links, *wrappers, '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'scoped-deep-rollback-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	declarations = source.read_text().split('owned ScopedChild relay_child(')[0]
	negative_cases = [
		('local-result', declarations + 'owned ScopedChild escape(){owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];var first=scoped_allocator<ScopedAllocator>(a,1,7);var second=scoped_allocator<ScopedAllocator>(b,1,7);var leaf=new HeapLeaf(11);var node=new HeapNode(11,move leaf);var tip=new(first)ScopedTip<int>(11,move node);var child=new(second)ScopedChild(11,move tip);return move child;}int main(){return 0;}', 'result retains a scoped local allocation'),
		('wrong-mode', source.read_text().replace('scoped_allocator<ScopedAllocator>(backing,2,1)', 'concurrent_allocator(2,8197,1,64)'), 'lifetime/thread contract differs'),
		('moved-input', source.read_text().replace('var forwarded=relay_child(move left);', 'var forwarded=relay_child(move left);left.read();'), 'moved'),
		('retired-backing', source.read_text().replace('if(context==null||child_context==null||tip_context==null)', 'release child_backing; if(context==null||child_context==null)'), 'exclusively borrowed'),
	]
	for name, text, diagnostic in negative_cases:
		negative = e.output / (name + '.astra')
		negative.write_text(text)
		e.run([e.compiler, '--check', negative, '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
