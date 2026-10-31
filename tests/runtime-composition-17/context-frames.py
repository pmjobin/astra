#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual selected frame storage across worker outcomes and anchor retirement."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-context-frames')
	here = Path(__file__).resolve().parent
	source = e.output / 'selected-workers.astra'
	text = (here / 'context-workers.astra').read_text().split('int main() {', 1)[0]
	text = text.replace('var one = calculate(move a);', 'var one = task_in(first, calculate(move a));').replace('var two = calculate(move b);', 'var two = task_in(second, calculate(move b));')
	needle = '\tif (concurrent_allocator_query(first, 1) != 0'
	assert text.count(needle) == 1
	exercise = '''
	{
		var guard = new FrameGuard(1);
		var cold = task_in(first, pending_frame(move guard));
	}
	var guard = new FrameGuard(2);
	var active = task_in(first, pending_frame(move guard));
	start(active);
	try { while (context_frame_is_pending() == 0) { await delay_ticks(1); } }
	catch (Error error) { await cancel_and_join(move active); throw; }
	await cancel_and_join(move active);
	var third = new FrameGuard(3);
	var failing = task_in(first, failing_frame(move third));
	bool failed = false;
	try { await move failing; } catch (Error error) { failed = true; }
	if (!failed) { throw new Error("missing selected-frame error"); }
'''
	text = text.replace(needle, exercise + needle)
	source.write_text(text + (here / 'context-frames.astra').read_text())
	sources = [source, ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'context-provider.c', here / 'context-worker-oracle.c', here / 'context-frame-oracle.c']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-custom.vapi']
	imports = [part for path in vapis for part in ['--vapi', path]]
	flags = ['-Wl,--wrap=astra_async_new_allocated']
	expected = 'context workers: two overlapping native threads, exact allocator origins, joined custom backing retirement\ncontext frames: six actual selected allocations/releases, cold drop, suspended cancel, checked failure, backing lease, unlocked callbacks\n'
	for level in ['O0', 'O1', 'O2']:
		obj, product = e.output / ('frames-' + level + '.o'), e.output / ('frames-' + level)
		e.run([e.compiler, '-' + level, '-c', *sources, *imports, '-o', obj])
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, here / 'context-frame-entry.c', *flags, '-o', product])
		e.run([product], stdout=expected, timeout=15)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'frames-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'frames', sources, providers, expected, sanitizer, flags, vapis=vapis)
	for name, context, argument in [('affine', 'affine_allocator(1,8197,7,64)', 'frame'), ('moved', 'concurrent_allocator(1,8197,7,64)', 'frame')]:
		negative = e.output / (name + '.astra')
		extra = 'var stolen = move frame;' if name == 'moved' else ''
		negative.write_text(f'async void child(){{}}int main(){{var frame={context};{extra}var task=task_in({argument},child());return 0;}}\n')
		e.run([e.compiler, '-c', negative, *sources[1:], '--vapi', vapis[0], '-o', e.output / (name + '.o')], expected=1)
		e.files(negative)
	e.files(*sources, *providers, *vapis, here / 'context-frame-entry.c', here / 'context-frames.astra', here / 'context-workers.astra', Path(__file__))
	for name in ['task-core17.c', 'task-api17.c', 'worker17.c', 'virtual.h', 'provider.h']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
