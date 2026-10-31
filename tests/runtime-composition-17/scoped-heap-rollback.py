#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe nested scoped trees, generic nodes, forwarding and rollback."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def modes(e, provider, vapi):
	base = '[Allocator(kind="context",context="scoped-affine")]class Leaf{private int value;init(int value){this.value=value;}int read(){return this.value;}}'
	for mode, factory, query in [('owned-affine', 'affine_allocator', 'affine_allocator_query'), ('owned-transfer', 'transferable_allocator', 'transfer_allocator_query'), ('owned-concurrent', 'concurrent_allocator', 'concurrent_allocator_query')]:
		api = vapi
		if mode == 'owned-transfer':
			api = e.output / 'transfer-query.vapi'
			api.write_text(vapi.read_text().replace('i64 affine_allocator_query(borrowed AffineAllocator context, int query);', 'i64 transfer_allocator_query(borrowed TransferAllocator context, int query);'))
			e.files(api)
		source = e.output / (mode + '.astra')
		source.write_text(base + '[Allocator(kind="context",context="' + mode + '")]class Node{private owned Leaf child;init(owned Leaf child){this.child=move child;}int read(){return this.child.read();}}[Allocator(kind="context",context="scoped-affine")]class Root{private owned Node child;init(owned Node child){this.child=move child;}int read(){return this.child.read();}}int main(){owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];var first=scoped_allocator<ScopedAllocator>(a,1,7);var second=scoped_allocator<ScopedAllocator>(b,2,1);var backing=' + factory + '(1,12293,7,64);if(first==null||second==null||backing==null){return 1;}{var leaf=new(first)Leaf(17);var node=new(backing)Node(move leaf);var root=new(second)Root(move node);if(root.read()!=17||scoped_allocator_query(first,1)!=1||scoped_allocator_query(second,1)!=1||' + query + '(backing,1)!=1){return 2;}}if(scoped_allocator_query(first,1)!=0||scoped_allocator_query(second,1)!=0||' + query + '(backing,1)!=0||' + query + '(backing,4)!=1||' + query + '(backing,5)!=1||scoped_allocator_query(first,4)!=1||scoped_allocator_query(first,5)!=1||scoped_allocator_query(second,4)!=1||scoped_allocator_query(second,5)!=1){return 3;}return 0;}')
		e.files(source)
		for level in ['O0', 'O1', 'O2']:
			product = e.output / (mode + '-' + level)
			e.run([e.compiler, '-' + level, source, '--vapi', api, '--link-object', provider, '--link-library', 'pthread', '-o', product])
			e.run([product], stdout='', timeout=15)
			e.files(product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / (mode + '-O2')], stdout='', contains='ERROR SUMMARY: 0 errors', timeout=45)


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-heap-rollback')
	here = Path(__file__).resolve().parent
	source = here / 'scoped-heap-rollback.astra'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'scoped-heap-rollback-oracle.c']
	e.files(source, vapi, *providers, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'lib/runtime/runtime/context-17.h')
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += [obj]
		e.files(obj)
	expected = 'scoped heap rollback: 2 contexts, 20 scoped placements, 14 heap roots, 28 heap children and 4 prefix failures\n'
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_open_scoped', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'free', 'calloc']]
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('scoped-heap-rollback-' + level)
		obj = product.with_suffix('.o')
		e.run([e.compiler, '-' + level, '-c', source, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-pthread', obj, *links, *wrappers, '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'scoped-heap-rollback-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	declarations = source.read_text().split('owned ScopedChild relay_child(')[0]
	negative_cases = [
		('local-result', declarations + 'owned ScopedChild escape(){owned u8[] a=new u8[8197];owned u8[] b=new u8[12289];var first=scoped_allocator<ScopedAllocator>(a,1,7);var second=scoped_allocator<ScopedAllocator>(b,1,7);var leaf=new HeapLeaf(11);var node=new HeapNode(11,move leaf);var tip=new(first)ScopedTip<int>(11,move node);var child=new ScopedChild(11,move tip);return move child;}int main(){return 0;}', 'result retains a scoped local allocation'),
		('wrong-mode', source.read_text().replace('scoped_allocator<ScopedAllocator>(backing,2,1)', 'concurrent_allocator(2,8197,1,64)'), 'lifetime/thread contract differs'),
		('moved-input', source.read_text().replace('var forwarded=relay_child(move left);', 'var forwarded=relay_child(move left);left.read();'), 'moved'),
		('retired-backing', source.read_text().replace('if(context==null||tip_context==null)', 'release tip_backing; if(context==null||tip_context==null)'), 'exclusively borrowed'),
	]
	for name, text, diagnostic in negative_cases:
		negative = e.output / (name + '.astra')
		negative.write_text(text)
		e.run([e.compiler, '--check', negative, '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative)
	modes(e, links[0], vapi)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
