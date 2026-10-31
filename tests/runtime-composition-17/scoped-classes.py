#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute caller-backed Class placement, refusal, reuse and record ownership."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-classes')
	here = Path(__file__).resolve().parent
	source = here / 'scoped-classes.astra'
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'scoped-classes-oracle.c']
	e.files(source, vapi, *providers, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py')
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += [obj]
		e.files(obj)
	expected = 'scoped Classes: distinct caller backing, pool refusal/reuse, record handoff, two generic layouts and 6 exact retirements\n'
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_open_scoped', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'free']]
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('scoped-classes-' + level)
		obj = product.with_suffix('.o')
		e.run([e.compiler, '-' + level, '-c', source, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-pthread', obj, *links, *wrappers, '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'scoped-classes-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	declarations = source.read_text().split('export(C) int scoped_classes_run() {')[0]
	negative_cases = [
		('local-result', declarations + '''owned ScopedItem escape() {
	owned u8[] backing = new u8[8197];
	var context = scoped_allocator<ScopedAllocator>(backing, 1, 7);
	var item = new(context)ScopedItem(1, 17);
	return move item;
}
int main(){return 0;}
''', 'result retains a scoped local allocation'),
		('outer-carrier', declarations + '''class Holder {
	private owned ScopedItem item;
	init(owned ScopedItem item){this.item=move item;}
	void put(owned ScopedItem item){this.item=move item;}
}
int main(){
	var outer=new Holder(null);
	owned u8[] backing=new u8[8197];
	{var context=scoped_allocator<ScopedAllocator>(backing,1,7);
	var item=new(context)ScopedItem(1,17);outer.put(move item);}
	return 0;
}
''', 'cannot outlive context'),
		('wrong-mode', declarations + '''int main(){
	var context=concurrent_allocator(2,8197,1,64);
	var item=new(context)ScopedItem(1,17);return 0;
}
''', 'lifetime/thread contract differs'),
		('moved-owner', source.read_text().replace('var joined = pair(move left, move right);', 'var joined = pair(move left, move right); observe(left);'), 'moved'),
		('retired-backing', source.read_text().replace('if (first == null || second == null)', 'release first_backing; if (first == null || second == null)'), 'exclusively borrowed'),
		('incomplete-body', declarations + '''extern(C) void* unknown_pointer();
int main(){
	owned u8[] backing=new u8[8197];
	var context=scoped_allocator<ScopedAllocator>(backing,1,7);
	var item=new(context)ScopedItem(1,17);unknown_pointer();return 0;
}
''', 'scoped lifetime proof is incomplete'),
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
