#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Hidden task producer exports a checked cold factory with exact ownership."""
from pathlib import Path
import shutil
import re
import runpy
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output, profile='owners'):
	e = Evidence(compiler, output, 'runtime-composition-17-checked-frame-units-' + profile)
	here = Path(__file__).resolve().parent
	text = (here / 'checked-frames.astra').read_text()
	assert profile in ['owners', 'buffers', 'records']
	if profile == 'records':
		text = (here / 'checked-frame-records.astra').read_text()
		e.files(here / 'checked-frame-records.astra')
	if profile == 'buffers':
		helper = here / 'checked-frame-buffers.py'
		text = runpy.run_path(str(helper))['buffer_captures'](text)
		e.files(helper)
	producer, consumer = text.split('export(C) int run_checked_frames()', 1)
	producer = 'namespace CheckedFrames;\n' + producer
	producer += '''
[ExceptionRoot] class Error {
	readonly string text;
	init(string text) { this.text = text; }
	virtual property string message { get { return this.text; } }
}
class ThreadedError : Error { init(string text) : base(text) {} }
enum ThreadedStatus { Completed, Cancelled }
async runtime ThreadedExecutor throws ThreadedError returns ThreadedStatus provider "posix-threaded";
'''
	consumer = 'export(C) int run_checked_frames()' + consumer
	names = ['CheckedFrameCargo', 'checked_frame_empty', 'checked_frame_consume', 'checked_frame_parent']
	if profile == 'records': names += ['CheckedFrameCapture', 'CheckedFrameEnvelope', 'checked_frame_record', 'checked_record_probe']
	for name in names:
		consumer = re.sub(r'\b' + name + r'\b', 'CheckedFrames.' + name, consumer)
	consumer = consumer.replace('catch (Error error)', 'catch (CheckedFrames.Error error)')
	consumer = '''// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
extern(C) void checked_frame_header_failure();
extern(C) int checked_frame_finish();
enum ThreadedStatus { Completed, Cancelled }
async runtime ThreadedExecutor throws CheckedFrames.ThreadedError returns ThreadedStatus provider "posix-threaded";
''' + consumer
	contexts = ROOT / 'lib/bindings/memory/contexts.vapi'
	vapis = [contexts]
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'checked-frames-oracle.c']
	flags = ['-Wl,--wrap=astra_async_try_new_allocated', '-Wl,--wrap=calloc']
	if profile == 'records':
		vapis.append(here / 'checked-frame-records.vapi')
		providers.append(here / 'checked-frame-records-oracle.c')
		flags += ['-Wl,--wrap=astra_context17_destroy', '-Wl,--wrap=checked_frame_finish']
	objects = []
	for source in providers:
		obj = e.output / (source.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', obj]); objects.append(obj); e.files(obj)
	expected = 'checked Source frames: pool/header refusal retains captures, admission empties slots, cold/error retirement and real executor recovery\n'
	for levels in ['00', '02', '20', '22', '11']:
		case = e.output / ('units-' + levels); case.mkdir(exist_ok=True)
		source = case / 'implementation.astra'; source.write_text(producer)
		selectors = ['Error', 'ThreadedError', 'CheckedFrameCargo', 'checked_frame_empty', 'checked_frame_consume', 'checked_frame_parent']
		if profile == 'records': selectors += ['CheckedFrameCapture<CheckedFrames.CheckedFrameCargo>', 'CheckedFrameEnvelope<CheckedFrames.CheckedFrameCargo>', 'checked_frame_record', 'checked_record_probe']
		exports = [arg for name in selectors for arg in ['--native-export', 'CheckedFrames.' + name]]
		e.run([e.compiler, '-O' + levels[0], '-c', source, *[arg for path in vapis for arg in ['--vapi', path]], '--module', 'CheckedFrames', *exports, '--emit-interface', case / 'producer.asti', '-o', case / 'producer.o'])
		assert 'checked-factory=nullable-unpublished/1;' in (case / 'producer.asti').read_text()
		sdk = case / 'sdk'; sdk.mkdir(exist_ok=True)
		for path in [case / 'producer.asti', case / 'producer.o', *vapis, *objects]: shutil.copyfile(path, sdk / path.name)
		shutil.copyfile(e.compiler, sdk / 'astrac'); (sdk / 'astrac').chmod(0o755)
		(sdk / 'consumer.astra').write_text(consumer)
		assert [p.name for p in sdk.glob('*.astra')] == ['consumer.astra']
		command = [sdk / 'astrac', '-O' + levels[1], '-c', sdk / 'consumer.astra', *[arg for path in vapis for arg in ['--vapi', sdk / path.name]], '--import-module', sdk / 'producer.asti', '-o', sdk / 'consumer.o']
		e.run(command, cwd=sdk)
		e.run(['cc', '-pthread', sdk / 'consumer.o', sdk / 'producer.o', *[sdk / p.name for p in objects], *flags, '-o', sdk / 'consumer'], cwd=sdk)
		e.run([sdk / 'consumer'], stdout=expected, cwd=sdk)
		if levels == '22':
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45, cwd=sdk)
			trace = sdk / 'opens.log'; e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
			assert str(source) not in trace.read_text() and str(sdk / 'producer.asti') in trace.read_text()
		e.files(source, *[p for p in sdk.iterdir() if p.is_file()])
	e.files(*providers, *vapis, here / 'checked-frames.astra', Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
