#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Whole nested owning records survive recoverable cold-frame refusal."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-checked-frame-records')
	here = Path(__file__).resolve().parent
	text = (here / 'checked-frame-records.astra').read_text()
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'checked-frames-oracle.c', here / 'checked-frame-records-oracle.c']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'checked-frame-records.vapi']
	imports = [arg for path in vapis for arg in ['--vapi', path]]
	flags = ['-Wl,--wrap=astra_async_try_new_allocated', '-Wl,--wrap=calloc', '-Wl,--wrap=astra_context17_destroy', '-Wl,--wrap=checked_frame_finish']
	expected = 'checked Source frames: pool/header refusal retains captures, admission empties slots, cold/error retirement and real executor recovery\n'
	for profile in ['threaded', 'virtual']:
		source = e.output / (profile + '.astra')
		source.write_text(text if profile == 'threaded' else text.replace('ThreadedExecutor', 'VirtualExecutor').replace('ThreadedStatus', 'RunStatus'))
		sources = [source, ROOT / ('lib/astra/async/' + profile + '.astra'), ROOT / 'lib/astra/base/errors.astra']
		cflags = ['-DM17_VIRTUAL'] if profile == 'virtual' else []
		for level in ['O0', 'O1', 'O2']:
			obj, product = e.output / (profile + '-' + level + '.o'), e.output / (profile + '-' + level)
			e.run([e.compiler, '-' + level, '-c', *sources, *imports, '-o', obj])
			e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *cflags, obj, *providers, *flags, '-o', product])
			e.run([product], stdout=expected, timeout=15); e.files(obj, product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / (profile + '-O2')], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
		for sanitizer in ['address', 'thread']: instrument(e, profile, sources, providers, expected, sanitizer, [*flags, *cflags], vapis=vapis, entry_symbol='run_checked_frames')
		e.files(*sources)
	base = text.split('export(C) int run_checked_frames()', 1)[0]
	for name, diagnostic, extra, body in [
		('unhandled-admission', 'unhandled checked exception bound', '', 'var frames=concurrent_allocator(1,16384,7,64);var objects=concurrent_allocator(1,16384,7,64);CheckedFrameEnvelope<CheckedFrameCargo> record=checked_frame_record(objects,1);var task=checked_task_in(frames,checked_frame_consume(move record));return 0;'),
		('copied-record', 'MOVE_VALUE argument requires an explicit move', '', 'var frames=concurrent_allocator(1,16384,7,64);var objects=concurrent_allocator(1,16384,7,64);CheckedFrameEnvelope<CheckedFrameCargo> record=checked_frame_record(objects,1);try{var task=checked_task_in(frames,checked_frame_consume(record));}catch(Error error){}return 0;'),
		('duplicate-record', 'duplicate record MOVE_VALUE argument', 'async void pair(CheckedFrameEnvelope<CheckedFrameCargo> first,CheckedFrameEnvelope<CheckedFrameCargo> second){}', 'var frames=concurrent_allocator(1,16384,7,64);var objects=concurrent_allocator(1,16384,7,64);CheckedFrameEnvelope<CheckedFrameCargo> record=checked_frame_record(objects,1);try{var task=checked_task_in(frames,pair(move record,move record));}catch(Error error){}return 0;'),
		('fresh-record', 'MOVE_VALUE argument requires an explicit move', '', 'var frames=concurrent_allocator(1,16384,7,64);var objects=concurrent_allocator(1,16384,7,64);try{var task=checked_task_in(frames,checked_frame_consume(checked_frame_record(objects,1)));}catch(Error error){}return 0;')]:
		negative = e.output / (name + '.astra'); negative.write_text(base + extra + 'int main(){' + body + '}')
		e.run([e.compiler, '-c', negative, ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra', *imports, '-o', e.output / (name + '.o')], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(*providers, *vapis, here / 'checked-frame-records.astra', Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
