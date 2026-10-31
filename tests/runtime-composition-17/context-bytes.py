#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual context-backed byte pairs preserve origin through owner composition."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output, profile='direct'):
	assert profile in ['direct', 'worker', 'affine', 'transfer', 'failure']
	e = Evidence(compiler, output, 'runtime-composition-17-context-bytes-' + profile)
	here = Path(__file__).resolve().parent
	source = here / 'context-bytes.astra'
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-custom.vapi']
	imports = [arg for path in vapis for arg in ['--vapi', path]]
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'context-provider.c', here / 'context-bytes-oracle.c']
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_allocate_mode', 'astra_context17_release_origin_checked']]
	sources = [source]
	entry_symbol = 'context_bytes_run'
	if profile in ['affine', 'transfer']:
		allocator, factory = ('AffineAllocator', 'affine_allocator') if profile == 'affine' else ('TransferAllocator', 'transferable_allocator')
		variant = e.output / (profile + '.astra')
		text = source.read_text().replace('ConcurrentAllocator', allocator)
		text = text.replace('custom_allocator(16387, 11)', factory + '(1, 16387, 11, 128)')
		text = text.replace('concurrent_allocator(2, 4099, 5, 64)', factory + '(1, 4099, 5, 64)')
		variant.write_text(text); sources = [variant]
		wrappers.append('-DCONTEXT_BYTES_' + profile.upper())
	if profile == 'worker':
		common = e.output / 'common.astra'; common.write_text('class ByteBridgeError:Error{init(string message):base(message){}}\nenum ByteServiceStatus{Completed,Cancelled}\nasync runtime ByteService throws ByteBridgeError returns ByteServiceStatus provider "virtual-composed";\n')
		data = e.output / 'data.astra'; data.write_text(source.read_text().split('export(C) int context_bytes_run()', 1)[0])
		sources = [common, data, here / 'context-bytes-worker.astra', here / 'context-bytes-driver.astra', ROOT / 'lib/astra/base/errors.astra']
		providers += [ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/platform/text-posix.c']
		vapis.append(ROOT / 'lib/bindings/async/composition.vapi')
		imports = [arg for path in vapis for arg in ['--vapi', path]]
		wrappers.append('-DCONTEXT_BYTES_WORKER')
		entry_symbol = 'context_bytes_worker_run'
	if profile == 'failure':
		data = e.output / 'data.astra'; data.write_text(source.read_text().split('export(C) int context_bytes_run()', 1)[0])
		sources = [data, here / 'context-bytes-failure.astra', ROOT / 'lib/astra/base/errors.astra']
		providers.append(ROOT / 'lib/runtime/platform/text-posix.c')
		vapis.append(here / 'context-bytes-failure.vapi')
		imports = [arg for path in vapis for arg in ['--vapi', path]]
		wrappers.append('-DCONTEXT_BYTES_FAILURE')
		entry_symbol = 'context_bytes_failure_run'
	e.files(source, *vapis, *providers, here / 'context-provider.h', Path(__file__))
	e.files(*sources)
	e.files(ROOT / 'tests/concurrency-runtime-13/sanitizers.py')
	expected = 'context bytes: actual independent backing, zeroing, result/field/record moves and original release\n'
	if profile == 'failure': expected = 'context bytes: actual exhaustion, caller input cleanup, recovery and exact backing release\n'
	for level in ['0', '1', '2']:
		obj, product = [e.output / ('bytes-O' + level + suffix) for suffix in ['.o', '']]
		e.run([e.compiler, '-O' + level, '-c', *sources, *imports, '-o', obj])
		e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, *wrappers, '-o', product])
		e.run([product], stdout=expected)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'bytes-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	for sanitizer in ['address', 'thread']:
		instrument(e, 'context-bytes', sources, providers, expected, sanitizer, link_flags=wrappers, vapis=vapis, entry_symbol=entry_symbol)
	if profile == 'worker':
		negative = e.output / 'affine-worker.astra'; negative.write_text((here / 'context-bytes-worker.astra').read_text().replace('ConcurrentAllocator', 'AffineAllocator'))
		e.run([e.compiler, '-c', common, negative, ROOT / 'lib/astra/base/errors.astra', *imports, '-o', e.output / 'negative.o'], expected=1)
		e.files(negative); e.complete(); return
	if profile in ['affine', 'transfer', 'failure']:
		e.complete(); return
	text = source.read_text()
	diagnostics = {
		'erased-result': 'exact owned buffer result',
		'erased-field': 'exact Resource type and cleanup contract',
		'wrong-mode': 'exact owned buffer result',
		'wrong-element': 'context byte allocation requires u8 elements and an exact owned allocator contract',
		'double-move': "use of moved owned value 'first'",
		'consumed-context': 'owner transfer overlaps an active borrowed callable argument',
	}
	for name, contents in {
		'erased-result': text.replace('owned ContextBytes<ConcurrentAllocator> make_context_bytes', 'owned u8[] make_context_bytes'),
		'erased-field': text.replace('private owned ContextBytes<ConcurrentAllocator> bytes;', 'private owned u8[] bytes;'),
		'wrong-mode': text.replace('owned ContextBytes<ConcurrentAllocator> first = make_context_bytes(19);', 'owned ContextBytes<AffineAllocator> first = make_context_bytes(19);'),
		'wrong-element': text.replace('new (context) u8[count]', 'new (context) int[count]'),
		'double-move': text.replace('var envelope = new ByteEnvelope(move first);', 'var other = move first; var envelope = new ByteEnvelope(move first);'),
		'consumed-context': text.replace('export(C) int context_bytes_run() {', 'int consume_context(owned ConcurrentAllocator value){return 19;} export(C) int context_bytes_run() {').replace('u8[count]', 'u8[consume_context(move context)]'),
	}.items():
		negative = e.output / (name + '.astra'); negative.write_text(contents)
		e.run([e.compiler, '-c', negative, *imports, '-o', e.output / 'negative.o'], expected=1, contains=diagnostics[name])
		e.files(negative)
	default = e.output / 'default.astra'; default.write_text('export(C) int default_bytes(){var bytes=new u8[7];bytes[3]=17;return bytes[3] as int;}\n')
	entry = e.output / 'default-entry.c'; entry.write_text('extern int default_bytes(void);int main(void){return default_bytes()-17;}\n')
	obj, product = e.output / 'default.o', e.output / 'default'
	e.run([e.compiler, '-O2', '-c', default, '-o', obj])
	undefined = e.run(['nm', '-u', obj]).stdout
	assert 'astra_context17_' not in undefined and 'calloc' in undefined and 'free' in undefined
	e.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', obj, entry, '-o', product])
	e.run([product], stdout='')
	e.files(default, entry, obj, product)
	empty = e.output / 'empty.astra'; empty.write_text('export(C) int context_bytes_run(){var context=concurrent_allocator(1,4099,5,64);if(context==null){return 1;}var bytes=new(context)u8[0];if(len(bytes)!=0||concurrent_allocator_query(context,1)!=0){return 2;}return 0;}\n')
	obj, product = e.output / 'empty.o', e.output / 'empty'
	e.run([e.compiler, '-O2', '-c', empty, *imports, '-o', obj])
	e.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, *wrappers, '-DCONTEXT_BYTES_EMPTY', '-o', product])
	e.run([product], stdout='')
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--errors-for-leak-kinds=all', product], stdout='', contains='ERROR SUMMARY: 0 errors')
	e.files(empty, obj, product)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
