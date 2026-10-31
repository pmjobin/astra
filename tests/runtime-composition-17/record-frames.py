#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Nested closed owning records in actual cooperative and worker frames."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output, mode='captures'):
	assert mode in ['captures', 'results']
	e = Evidence(compiler, output, 'runtime-composition-17-record-frames-' + mode)
	here = Path(__file__).resolve().parent
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'record-frames-oracle.c']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'record-frames.vapi']
	flags = ['-Wl,--wrap=astra_context17_destroy', '-Wl,--wrap=astra_context17_release_origin_checked', '-Wl,--wrap=astra_async_complete']
	imports = [arg for path in vapis for arg in ['--vapi', path]]
	expected = 'owning record frames: cold capture, suspended locals, success/error/cancel and exact joined field retirement\n'
	if mode == 'results': expected += 'owning record results: observed transfer and published discarded success, exact field retirement\n'
	for profile in ['threaded', 'virtual']:
		source = e.output / (profile + '.astra'); text = (here / 'record-frames.astra').read_text()
		if mode == 'results':
			insertion = 'if (concurrent_allocator_query(frames, 1) != 0)'
			assert text.count(insertion) == 1
			text = text.replace(insertion, 'try { var executor = ThreadedExecutor.open(2); var status = executor.run(task_in(frames, frame_record_results())); } catch (Error error) { return 11; }\n\t' + insertion)
			text += (here / 'record-results.astra').read_text()
		if profile == 'virtual': text = text.replace('ThreadedExecutor', 'VirtualExecutor').replace('ThreadedStatus', 'RunStatus')
		else: text = text.replace(' executor.advance(1);', '')
		source.write_text(text)
		sources = [source, ROOT / ('lib/astra/async/' + profile + '.astra'), ROOT / 'lib/astra/base/errors.astra']
		cflags = ['-DM17_VIRTUAL'] if profile == 'virtual' else []
		if mode == 'results': cflags.append('-DM17_RECORD_RESULTS')
		for level in ['O0', 'O1', 'O2']:
			obj, product = e.output / (profile + '-' + level + '.o'), e.output / (profile + '-' + level)
			e.run([e.compiler, '-' + level, '-c', *sources, *imports, '-o', obj])
			e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *cflags, obj, *providers, *flags, '-o', product])
			e.run([product], stdout=expected, timeout=20); e.files(obj, product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / (profile + '-O2')], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
		for sanitizer in ['address', 'thread']: instrument(e, profile, sources, providers, expected, sanitizer, [*cflags, *flags], vapis=vapis, entry_symbol='run_record_frames')
		e.files(*sources)
	base = (here / 'record-frames.astra').read_text().split('export(C) int run_record_frames()', 1)[0]
	for name, extra, body in [
		('read-after-capture', '', 'FrameEnvelope<FrameRecordItem> record=frame_record(17);var task=consume_frame_record(move record,0);return record.stamp;'),
		('capture-twice', '', 'FrameEnvelope<FrameRecordItem> record=frame_record(17);var task=consume_frame_record(move record,0);var other=consume_frame_record(move record,0);return 0;'),
		('borrowed-record', 'async void reject(borrowed FrameEnvelope<FrameRecordItem> record){}', 'return 0;'),
		('affine-record', '[Allocator(kind="context",context="owned-affine")]class AffineItem{init(){}}struct AffineRecord{owned AffineItem item;}async void reject(AffineRecord record){}', 'var context=affine_allocator(1,8192,7,64);var item=new(context)AffineItem();AffineRecord record={item=move item};var task=reject(move record);return 0;')]:
		negative = e.output / (name + '.astra'); negative.write_text(base + extra + 'int main(){' + body + '}')
		e.run([e.compiler, '-c', negative, ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra', *imports, '-o', e.output / (name + '.o')], expected=1)
		e.files(negative)
	e.files(*providers, *vapis, here / 'record-frames.astra', Path(__file__))
	if mode == 'results': e.files(here / 'record-results.astra')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
