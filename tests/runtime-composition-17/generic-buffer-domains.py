#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Generic materialization preserves context-buffer cleanup domains."""
from pathlib import Path
import resource
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument

SOURCE = '''
struct Box<T> { T value; }
Box<int> box(int number) { Box<int> result = {value = number}; return result; }
owned ContextBytes<ConcurrentAllocator> concurrent_bytes() {
	var context = concurrent_allocator(1, 8191, 7, 128);
	var bytes = new(context)u8[17]; bytes[0] = 17; return move bytes;
}
owned ContextBytes<AffineAllocator> affine_bytes() {
	var context = affine_allocator(1, 8191, 7, 64);
	var bytes = new(context)u8[19]; bytes[0] = 19; return move bytes;
}
owned ContextBytes<TransferAllocator> transfer_bytes() {
	var context = transferable_allocator(1, 8191, 7, 256);
	var bytes = new(context)u8[23]; bytes[0] = 23; return move bytes;
}
int byte_value(u8[] bytes) { return bytes[0] as int; }
export(C) int buffer_domains_run() {
	{
		var first = concurrent_bytes(); var second = affine_bytes(); var third = transfer_bytes();
		var ordinary = new u8[31]; ordinary[0] = 31;
		var result = box(7);
		if (byte_value(first) + byte_value(second) + byte_value(third) + byte_value(ordinary) + result.value != 97) { return 1; }
	}
	return buffer_domains_finish();
}
extern(C) int buffer_domains_finish();
'''


def main(compiler, output):
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	e = Evidence(compiler, output, 'runtime-composition-17-generic-buffer-domains')
	here = Path(__file__).resolve().parent
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'generic-buffer-domains-oracle.c']
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_allocate_mode', 'astra_context17_release_origin_checked']]
	fixture = here / 'freeze-2-buffer-domains.astra'
	source = e.output / 'domains.astra'; source.write_text(SOURCE)
	expected = 'generic buffer domains: three allocator modes, borrowed views and exact closed-origin releases\n'
	for level in ['0', '1', '2']:
		obj, product = [e.output / ('domains-O' + level + suffix) for suffix in ['.o', '']]
		e.run([e.compiler, '-O' + level, '-c', source, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, *wrappers, '-o', product])
		e.run([product], stdout=expected); e.files(obj, product)
		original = e.output / ('original-O' + level)
		context = e.output / 'context.o'
		if level == '0': e.run(['cc', '-O2', '-std=c11', '-pthread', '-c', providers[0], '-o', context])
		e.run([e.compiler, '-O' + level, fixture, '--vapi', vapi, '--link-object', context, '--link-library', 'pthread', '-o', original])
		e.run([original], stdout=''); e.files(original)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	instrument(e, 'domains', [source], providers, expected, 'address', link_flags=wrappers, vapis=[vapi], entry_symbol='buffer_domains_run')
	for name, text, diagnostic in [
		('erased-origin', SOURCE.replace('owned ContextBytes<AffineAllocator> affine_bytes()', 'owned u8[] affine_bytes()'), 'exact owned buffer result'),
		('wrong-mode', SOURCE.replace('var second = affine_bytes();', 'owned ContextBytes<ConcurrentAllocator> second = affine_bytes();'), 'exact owned buffer result'),
		('double-move', SOURCE.replace('var ordinary = new u8[31];', 'var taken = move first; var twice = move first; var ordinary = new u8[31];'), "moved owned value 'first'"),
	]:
		path = e.output / (name + '.astra'); path.write_text(text)
		e.run([e.compiler, '-c', path, '--vapi', vapi, '-o', e.output / 'negative.o'], expected=1, contains=diagnostic); e.files(path)
	e.files(source, fixture, vapi, *providers, context, Path(__file__), ROOT / 'lib/runtime/runtime/context-17.h', ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
