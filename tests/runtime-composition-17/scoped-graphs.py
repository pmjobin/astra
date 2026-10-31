#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute independent scoped parent/child storage and exact field retirement."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-graphs')
	here = Path(__file__).resolve().parent
	source = here / 'scoped-graphs.astra'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'scoped-graphs-oracle.c']
	e.files(source, vapi, *providers, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py')
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += [obj]
		e.files(obj)
	expected = 'scoped graphs: 2 contexts, ordinary/generic parents, refusal preservation and 7 exact retirements\n'
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_open_scoped', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'free']]
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('scoped-graphs-' + level)
		obj = product.with_suffix('.o')
		e.run([e.compiler, '-' + level, '-c', source, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-pthread', obj, *links, *wrappers, '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'scoped-graphs-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	declarations = source.read_text().split('owned ScopedHost relay_host(')[0]
	negative_cases = [
		('local-result', declarations + 'owned ScopedHost escape(){owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];var first=scoped_allocator<ScopedAllocator>(a,1,7);var second=scoped_allocator<ScopedAllocator>(b,1,7);var left=new(first)ScopedLeaf(1,17);var host=new(second)ScopedHost(3,move left,null);return move host;}int main(){return 0;}', 'result retains a scoped local allocation'),
		('unproved-owner-transport', declarations + 'int consume(owned ScopedHost input){return input.read();}int main(){return 0;}', 'complete emitted ABI authority: consume'),
		('moved-child', source.read_text().replace('if(host.read()!=40)', 'left.read();if(host.read()!=40)'), 'moved'),
		('wrong-mode', source.read_text().replace('var second=scoped_allocator<ScopedAllocator>(second_backing,2,1);', 'var second=concurrent_allocator(2,12289,1,64);'), 'lifetime/thread contract differs'),
		('retired-backing', source.read_text().replace('if(host.read()!=40)', 'release first_backing;if(host.read()!=40)'), 'exclusively borrowed'),
		('incomplete-body', source.read_text().replace('extern(C) void scoped_graph_constructed', 'extern(C) void* unknown_pointer();extern(C) void scoped_graph_constructed').replace('if(host.read()!=40)', 'unknown_pointer();if(host.read()!=40)'), 'scoped lifetime proof is incomplete'),
	]
	for name, text, diagnostic in negative_cases:
		negative = e.output / (name + '.astra')
		negative.write_text(text)
		e.run([e.compiler, '--check', negative, '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(ROOT / 'lib/runtime/runtime/context-17.h')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
