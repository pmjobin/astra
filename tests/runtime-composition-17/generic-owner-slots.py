#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Frozen failure regression: generic cloning preserves scalar owner-slot roles."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-generic-owner-slots')
	here = Path(__file__).resolve().parent
	fixture = here / 'freeze-1-owner-slot.astra'
	text = fixture.read_text().replace('observe(0, len(this.items), 0);', 'observe(0, len(this.items), 0); observe(1, this.items.capacity, len(this.items)); check_reserve(this.items.reserve(5)); observe(2, inspect_item(this.items[len(this.items) - 1]), 0);')
	assert text != fixture.read_text()
	text += '''
extern(C) void observed_reserve(int result);
void check_reserve(bool result) { if (result) { observed_reserve(1); } else { observed_reserve(0); } }
extern(C) int slots_finish();
int inspect_item(borrowed Item item) { return item.number; }
int main() {
	var context = concurrent_allocator(1, 65539, 17, 128);
	if (context == null) { return 1; }
	{
		var store = new(context) Store(3);
		var first = new Item(17); store.publish(move first);
		var second = new Item(23); store.publish(move second);
		var packet = make_packet(31); if (packet.value.number != 31) { return 2; }
	}
	if (concurrent_allocator_query(context, 1) != 0) { return 3; }
	return slots_finish();
}
'''
	source = e.output / 'generic-slots.astra'; source.write_text(text)
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/runtime/monitors-13.c', here / 'generic-owner-slots-oracle.c']
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]; e.files(obj)
	expected = 'generic owner slots: copied length/capacity/reserve retain scalar call roles and exact backing retirement\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('generic-slots-' + level)
		e.run([e.compiler, '-' + level, source, '--vapi', vapi, *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected); e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	instrument(e, 'generic-slots', [source], providers, expected, 'address', vapis=[vapi])
	e.files(source, fixture, vapi, *providers, Path(__file__), ROOT / 'lib/runtime/runtime/context-17.h', ROOT / 'lib/runtime/runtime/monitors-13.h', ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
