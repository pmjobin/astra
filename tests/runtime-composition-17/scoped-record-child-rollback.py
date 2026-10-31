#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe scoped child origins and checked initialized-prefix rollback."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-record-child-rollback')
	here = Path(__file__).resolve().parent
	source = here / 'scoped-record-child-rollback.astra'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'scoped-record-child-rollback-oracle.c']
	e.files(source, vapi, *providers, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'lib/runtime/runtime/context-17.h')
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += [obj]
		e.files(obj)
	expected = 'scoped record child rollback: 2 contexts, 20 placements, 28 heap child retirements and 4 prefix failures\n'
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_open_scoped', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'free']]
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('scoped-record-child-rollback-' + level)
		obj = product.with_suffix('.o')
		e.run([e.compiler, '-' + level, '-c', source, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-pthread', obj, *links, *wrappers, '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'scoped-record-child-rollback-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	for profile in ['nested', 'generic']:
		text = source.read_text()
		if profile == 'nested':
			text = text.replace('struct ChildPacket{owned ScopedChild item;int tag;}', 'struct ChildInner{owned ScopedChild item;}struct ChildPacket{ChildInner inner;int tag;}')
			for name in ['left', 'right', 'retained_left', 'retained_right']:
				text = text.replace('{item=move ' + name + ',tag=', '{inner={item=move ' + name + '},tag=')
		else:
			text = text.replace('struct ChildPacket{owned ScopedChild item;int tag;}', 'struct ChildPacket<T>where T:Ownable{owned T item;int tag;}')
			text = text.replace('ChildPacket ', 'ChildPacket<ScopedChild> ')
		variant = e.output / (profile + '.astra')
		variant.write_text(text)
		e.files(variant)
		for level in ['O0', 'O1', 'O2']:
			product = e.output / (profile + '-' + level)
			obj = product.with_suffix('.o')
			e.run([e.compiler, '-' + level, '-c', variant, '--vapi', vapi, '-o', obj])
			e.run(['cc', '-pthread', obj, *links, *wrappers, '-o', product])
			e.run([product], stdout=expected, timeout=15)
			e.files(obj, product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / (profile + '-O2')], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	declarations = source.read_text().split('export(C) int scoped_record_child_rollback_run()')[0]
	negative_cases = [
		('local-result', declarations + '''owned CheckedScopedParent escape() throws ChildConstructionFault {
	owned u8[] a=new u8[8197]; owned u8[] b=new u8[12289];
	var context=scoped_allocator<ScopedAllocator>(a,2,1);
	var child_context=scoped_allocator<ScopedAllocator>(b,1,7);
	var left_leaf=new HeapLeaf(11); var left_node=new HeapNode(11,move left_leaf);
	var left=new(child_context)ScopedChild(11,move left_node);
	var right_leaf=new HeapLeaf(12); var right_node=new HeapNode(12,move right_leaf);
	var right=new(child_context)ScopedChild(12,move right_node);ChildPacket left_packet={item=move left,tag=11};ChildPacket right_packet={item=move right,tag=12};
	var host=new(context)CheckedScopedParent(1,move left_packet,move right_packet,0);
	return move host;
}
int main(){return 0;}
''', 'result retains a scoped local allocation'),
		('wrong-mode', source.read_text().replace('scoped_allocator<ScopedAllocator>(backing,2,1)', 'concurrent_allocator(2,8197,1,64)'), 'lifetime/thread contract differs'),
		('moved-input', source.read_text().replace('if(host.read()!=identity*20+3)', 'consume_packet(move left_packet); if(host.read()!=identity*20+3)'), 'moved'),
		('retired-backing', source.read_text().replace('if(context==null||child_context==null)', 'release child_backing; if(context==null||child_context==null)'), 'exclusively borrowed'),
	]
	for name, text, diagnostic in negative_cases:
		negative = e.output / (name + '.astra')
		negative.write_text(text)
		e.run([e.compiler, '--check', negative, '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
