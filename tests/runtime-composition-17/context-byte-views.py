#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Context byte views borrow actual storage without erasing owning release."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-byte-views')
	here = Path(__file__).resolve().parent
	source = here / 'context-byte-views.astra'
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-custom.vapi']
	imports = [arg for path in vapis for arg in ['--vapi', path]]
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'context-provider.c', here / 'context-byte-views-oracle.c']
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_allocate_mode', 'astra_context17_release_origin_checked']]
	expected = 'context byte views: exact nonescaping Astra/C storage, closed anchor and original final release\n'
	e.files(source, *vapis, *providers, here / 'context-provider.h', Path(__file__), ROOT / 'tests/concurrency-runtime-13/sanitizers.py')
	for level in ['0', '1', '2']:
		obj, product = [e.output / ('views-O' + level + suffix) for suffix in ['.o', '']]
		e.run([e.compiler, '-O' + level, '-c', source, *imports, '-o', obj])
		e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, *wrappers, '-o', product])
		e.run([product], stdout=expected); e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'views-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	for sanitizer in ['address', 'thread']:
		instrument(e, 'views', [source], providers, expected, sanitizer, link_flags=wrappers, vapis=vapis, entry_symbol='context_byte_views_run')
	text = source.read_text()
	diagnostics = {'owned-erasure': 'exact owned buffer result', 'persistent-view': 'escaping slice', 'wrong-element': "expects type 'int[]'", 'borrow-transfer': "cannot borrow moved owned value 'bytes'"}
	for name, contents in {
		'owned-erasure': text.replace('release bytes;', 'owned u8[] erased = move bytes;'),
		'persistent-view': text.replace('close_view_anchor(move context);', 'u8[] view = bytes; close_view_anchor(move context);'),
		'wrong-element': text.replace('int mutate_byte_view(u8[] bytes)', 'int mutate_byte_view(int[] bytes)'),
		'borrow-transfer': text.replace('int mutate_byte_view(u8[] bytes)', 'int mutate_byte_view(u8[] bytes, owned ContextBytes<ConcurrentAllocator> owner)').replace('mutate_byte_view(bytes)', 'mutate_byte_view(bytes, move bytes)'),
	}.items():
		negative = e.output / (name + '.astra'); negative.write_text(contents)
		e.run([e.compiler, '-c', negative, *imports, '-o', e.output / 'negative.o'], expected=1, contains=diagnostics[name])
		e.files(negative)
	negative = e.output / 'async-retention.astra'
	negative.write_text('enum ViewStatus{Completed,Cancelled}async runtime ViewExecutor throws Error returns ViewStatus provider "virtual-composed";async int retain(borrowed u8[] bytes)throws Error{await delay_ticks(1);return len(bytes);}async void escape(owned ContextBytes<ConcurrentAllocator> bytes)throws Error{int count=await retain(bytes);}int main(){return 0;}\n')
	e.run([e.compiler, '-c', negative, ROOT / 'lib/astra/base/errors.astra', *imports, '-o', e.output / 'negative.o'], expected=1, contains='borrowed async capture requires a fresh directly awaited child and sealed fixed parent-local array view')
	e.files(negative)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
