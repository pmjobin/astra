#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe owned input retention and initialized-prefix rollback before catch."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def modes(e, provider, vapi):
	leaf = '[Allocator(kind="context",context="scoped-affine")]class Leaf{private int value;init(int value){this.value=value;}int read(){return this.value;}}'
	for mode, factory, query in [('heap', '', ''), ('owned-affine', 'affine_allocator', 'affine_allocator_query'), ('owned-transfer', 'transferable_allocator', 'transfer_allocator_query'), ('owned-concurrent', 'concurrent_allocator', 'concurrent_allocator_query')]:
		api = vapi
		if mode == 'owned-transfer':
			api = e.output / 'transfer-query.vapi'
			api.write_text(vapi.read_text().replace('i64 affine_allocator_query(borrowed AffineAllocator context, int query);', 'i64 transfer_allocator_query(borrowed TransferAllocator context, int query);'))
			e.files(api)
		policy = '' if mode == 'heap' else '[Allocator(kind="context",context="' + mode + '")]'
		opened = '' if mode == 'heap' else 'var parent=' + factory + '(1,12293,7,64);if(parent==null){return 1;}'
		allocated = 'new Host' if mode == 'heap' else 'new(parent)Host'
		live = '' if mode == 'heap' else '||' + query + '(parent,1)!=1'
		retired = '' if mode == 'heap' else '||' + query + '(parent,1)!=0||' + query + '(parent,4)!=1||' + query + '(parent,5)!=1'
		source = e.output / (mode + '.astra')
		source.write_text(leaf + policy + 'class Host{private owned Leaf child;private owned u8[] bytes;private owned i32[] values;init(owned Leaf child,owned u8[] bytes,owned i32[] values){this.child=move child;this.bytes=move bytes;this.values=move values;}int read(){return this.child.read()+len(this.bytes)+len(this.values);}}owned Host relay(owned Host input){return move input;}int main(){owned u8[] backing=new u8[8197];var context=scoped_allocator<ScopedAllocator>(backing,2,1);if(context==null){return 1;}' + opened + '{var leaf=new(context)Leaf(17);owned u8[] bytes=new u8[37];owned i32[] values=new i32[53];var initial=' + allocated + '(move leaf,move bytes,move values);var host=relay(move initial);if(host.read()!=107||scoped_allocator_query(context,1)!=1' + live + '){return 2;}}if(scoped_allocator_query(context,1)!=0||scoped_allocator_query(context,4)!=1||scoped_allocator_query(context,5)!=1' + retired + '){return 3;}return 0;}')
		e.files(source)
		for level in ['O0', 'O1', 'O2']:
			product = e.output / (mode + '-' + level)
			e.run([e.compiler, '-' + level, source, '--vapi', api, '--link-object', provider, '--link-library', 'pthread', '-o', product])
			e.run([product], stdout='', timeout=15)
			e.files(product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / (mode + '-O2')], stdout='', contains='ERROR SUMMARY: 0 errors', timeout=45)


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-buffer-graph-rollback')
	here = Path(__file__).resolve().parent
	source = here / 'scoped-buffer-graph-rollback.astra'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'scoped-buffer-graph-rollback-oracle.c']
	e.files(source, vapi, *providers, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'lib/runtime/runtime/context-17.h')
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += [obj]
		e.files(obj)
	expected = 'scoped buffer graph rollback: 13 placements, 4 prefix failures, 7 scoped children and 14 buffers retired before backing\n'
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_open_scoped', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'free', 'calloc']]
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('scoped-buffer-graph-rollback-' + level)
		obj = product.with_suffix('.o')
		e.run([e.compiler, '-' + level, '-c', source, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-pthread', obj, *links, *wrappers, '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'scoped-buffer-graph-rollback-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	declarations = source.read_text().split('export(C) int scoped_buffer_graph_rollback_run()')[0]
	negative_cases = [
		('local-result', declarations + """owned CheckedBufferHost escape() throws BufferConstructionFault {
	owned u8[] backing=new u8[8197];
	var context=scoped_allocator<ScopedAllocator>(backing,2,1);
	var child=new(context)BufferGraphLeaf(1);
	owned u8[] left=new u8[11];
	owned i32[] right=new i32[13];
	var host=new(context)CheckedBufferHost(1,move child,move left,move right,0);
	return move host;
}
int main(){return 0;}
""", 'result retains a scoped local allocation'),
		('wrong-mode', source.read_text().replace('scoped_allocator<ScopedAllocator>(backing,2,1)', 'concurrent_allocator(2,8197,1,64)'), 'lifetime/thread contract differs'),
		('moved-input', source.read_text().replace('if(host.read()!=identity*21+4)', 'len(left); if(host.read()!=identity*21+4)'), 'moved'),
		('retired-backing', source.read_text().replace('if(context==null||leaf_context==null)', 'release backing; if(context==null||leaf_context==null)'), 'exclusively borrowed'),
		('retired-child-backing', source.read_text().replace('if(context==null||leaf_context==null)', 'release leaf_backing; if(context==null||leaf_context==null)'), 'exclusively borrowed'),
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
