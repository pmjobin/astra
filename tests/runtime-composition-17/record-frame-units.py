#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Opaque native tasks capture nested owning records and retire each field."""
from pathlib import Path
import re
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output, mode='captures'):
	assert mode in ['captures', 'results']
	e = Evidence(compiler, output, 'runtime-composition-17-record-frame-units-' + mode)
	here = Path(__file__).resolve().parent
	producer, consumer = (here / 'record-frames.astra').read_text().split('export(C) int run_record_frames()', 1)
	consumer = 'export(C) int run_record_frames()' + consumer
	names = ['FrameRecordItem', 'FrameRecord', 'FrameEnvelope', 'frame_record', 'consume_frame_record', 'local_frame_record']
	if mode == 'results':
		producer += (here / 'record-results.astra').read_text()
		needle = 'if (concurrent_allocator_query(frames, 1) != 0)'
		assert consumer.count(needle) == 1
		consumer = consumer.replace(needle, 'try { var executor = ThreadedExecutor.open(2); var status = executor.run(task_in(frames, frame_record_results())); } catch (Error error) { return 11; }\n\t' + needle)
		names += ['produce_frame_record', 'frame_record_results']
	producer = 'namespace RecordFrames;\n' + producer + '''
[ExceptionRoot] class Error {
	readonly string text;
	init(string text) { this.text = text; }
	virtual property string message { get { return this.text; } }
}
class ThreadedError : Error { init(string text) : base(text) {} }
enum ThreadedStatus { Completed, Cancelled }
async runtime ThreadedExecutor throws ThreadedError returns ThreadedStatus provider "posix-threaded";
'''
	for name in names: consumer = re.sub(r'\b' + name + r'\b', 'RecordFrames.' + name, consumer)
	consumer = consumer.replace('catch (Error error)', 'catch (RecordFrames.Error error)').replace(' executor.advance(1);', '')
	consumer = '''// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
extern(C) int record_frame_pending();
extern(C) int record_frame_finish();
enum ThreadedStatus { Completed, Cancelled }
async runtime ThreadedExecutor throws RecordFrames.ThreadedError returns ThreadedStatus provider "posix-threaded";
''' + consumer
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'record-frames.vapi']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'record-frames-oracle.c']
	flags = ['-Wl,--wrap=astra_context17_destroy', '-Wl,--wrap=astra_context17_release_origin_checked', '-Wl,--wrap=astra_async_complete']
	cflags = ['-DM17_RECORD_RESULTS'] if mode == 'results' else []
	objects = []
	for source in providers:
		obj = e.output / (source.stem + '.o'); objects.append(obj)
		e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *cflags, '-c', source, '-o', obj]); e.files(obj)
	expected = 'owning record frames: cold capture, suspended locals, success/error/cancel and exact joined field retirement\n'
	if mode == 'results': expected += 'owning record results: observed transfer and published discarded success, exact field retirement\n'
	selectors = ['Error', 'ThreadedError', 'FrameRecordItem', 'FrameRecord<RecordFrames.FrameRecordItem>', 'FrameEnvelope<RecordFrames.FrameRecordItem>', 'frame_record', 'consume_frame_record', 'local_frame_record']
	if mode == 'results': selectors += ['produce_frame_record', 'frame_record_results']
	exports = [arg for name in selectors for arg in ['--native-export', 'RecordFrames.' + name]]
	for levels in ['00', '02', '20', '22', '11']:
		case = e.output / ('units-' + levels); case.mkdir(exist_ok=True)
		source = case / 'implementation.astra'; source.write_text(producer)
		e.run([e.compiler, '-O' + levels[0], '-c', source, *[arg for p in vapis for arg in ['--vapi', p]], '--module', 'RecordFrames', *exports, '--emit-interface', case / 'producer.asti', '-o', case / 'producer.o'])
		sdk = case / 'sdk'; sdk.mkdir(exist_ok=True)
		for path in [case / 'producer.asti', case / 'producer.o', *vapis, *objects]: shutil.copyfile(path, sdk / path.name)
		shutil.copyfile(e.compiler, sdk / 'astrac'); (sdk / 'astrac').chmod(0o755)
		(sdk / 'consumer.astra').write_text(consumer)
		assert [p.name for p in sdk.glob('*.astra')] == ['consumer.astra']
		command = [sdk / 'astrac', '-O' + levels[1], '-c', sdk / 'consumer.astra', *[arg for p in vapis for arg in ['--vapi', sdk / p.name]], '--import-module', sdk / 'producer.asti', '-o', sdk / 'consumer.o']
		e.run(command, cwd=sdk)
		e.run(['cc', '-pthread', sdk / 'consumer.o', sdk / 'producer.o', *[sdk / p.name for p in objects], *flags, '-o', sdk / 'consumer'], cwd=sdk)
		e.run([sdk / 'consumer'], stdout=expected, cwd=sdk, timeout=20)
		if levels == '22':
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60, cwd=sdk)
			trace = sdk / 'opens.log'; e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
			assert str(source) not in trace.read_text() and str(sdk / 'producer.asti') in trace.read_text()
		e.files(source, *[p for p in sdk.iterdir() if p.is_file()])
	e.files(*providers, *vapis, here / 'record-frames.astra', here / 'record-results.astra', Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
