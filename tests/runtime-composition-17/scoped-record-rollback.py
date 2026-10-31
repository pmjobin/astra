#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe owned input retention and initialized-prefix rollback before catch."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-record-rollback')
	here = Path(__file__).resolve().parent
	source = here / 'scoped-record-rollback.astra'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'scoped-record-rollback-oracle.c']
	e.files(source, vapi, *providers, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'lib/runtime/runtime/context-17.h')
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += [obj]
		e.files(obj)
	expected = 'scoped record rollback: 6 placements, 4 prefix failures, 21 child retirements and retained refusal records\n'
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_open_scoped', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'free']]
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('scoped-record-rollback-' + level)
		obj = product.with_suffix('.o')
		e.run([e.compiler, '-' + level, '-c', source, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-pthread', obj, *links, *wrappers, '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'scoped-record-rollback-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	for profile in ['nested', 'generic']:
		text = source.read_text()
		if profile == 'nested':
			text = text.replace('struct LeftPacket{owned HeapLeaf item;int tag;}', 'struct LeftInner{owned HeapLeaf item;}struct LeftPacket{LeftInner inner;int tag;}')
			text = text.replace('struct RightPacket{owned HeapNode item;int tag;}', 'struct RightInner{owned HeapNode item;}struct RightPacket{RightInner inner;int tag;}')
			for name in ['left', 'right', 'retained_left', 'retained_right']:
				text = text.replace('{item=move ' + name + ',tag=', '{inner={item=move ' + name + '},tag=')
		else:
			text = text.replace('struct LeftPacket{owned HeapLeaf item;int tag;}', 'struct LeftPacket<T>where T:Ownable{owned T item;int tag;}')
			text = text.replace('struct RightPacket{owned HeapNode item;int tag;}', 'struct RightPacket<T>where T:Ownable{owned T item;int tag;}')
			text = text.replace('LeftPacket ', 'LeftPacket<HeapLeaf> ').replace('RightPacket ', 'RightPacket<HeapNode> ')
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
	declarations = source.read_text().split('export(C) int scoped_record_rollback_run()')[0]
	negative_cases = [
		('local-result', declarations + '''owned CheckedScopedHost escape() throws OwnedConstructionFault {
	owned u8[] backing=new u8[8197];
	var context=scoped_allocator<ScopedAllocator>(backing,2,1);
	var left=new HeapLeaf(11);
	var leaf=new HeapLeaf(12);
	var right=new HeapNode(13,move leaf);
	LeftPacket left_packet={item=move left,tag=11};
	RightPacket right_packet={item=move right,tag=12};
	var host=new(context)CheckedScopedHost(1,move left_packet,move right_packet,0);
	return move host;
}
int main(){return 0;}
''', 'result retains a scoped local allocation'),
		('wrong-mode', source.read_text().replace('scoped_allocator<ScopedAllocator>(backing,2,1)', 'concurrent_allocator(2,8197,1,64)'), 'lifetime/thread contract differs'),
		('moved-input', source.read_text().replace('if(host.read()!=identity*20+3)', 'consume_left(move left_packet); if(host.read()!=identity*20+3)'), 'moved'),
		('retired-backing', source.read_text().replace('if(context==null)', 'release backing; if(context==null)'), 'exclusively borrowed'),
	]
	for name, text, diagnostic in negative_cases:
		negative = e.output / (name + '.astra')
		negative.write_text(text)
		e.run([e.compiler, '--check', negative, '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
