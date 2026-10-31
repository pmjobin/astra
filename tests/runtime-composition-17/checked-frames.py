#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Source checked frame admission with actual backing and header refusal."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-checked-frames')
	here = Path(__file__).resolve().parent
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi']
	imports = [part for path in vapis for part in ['--vapi', path]]
	expected = 'checked Source frames: pool/header refusal retains captures, admission empties slots, cold/error retirement and real executor recovery\n'
	flags = ['-Wl,--wrap=astra_async_try_new_allocated', '-Wl,--wrap=calloc']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'checked-frames-oracle.c']
	for profile in ['threaded', 'virtual']:
		source = e.output / (profile + '.astra')
		text = (here / 'checked-frames.astra').read_text()
		if profile == 'virtual':
			text = text.replace('ThreadedExecutor', 'VirtualExecutor').replace('ThreadedStatus', 'RunStatus')
		source.write_text(text)
		sources = [source, ROOT / ('lib/astra/async/' + profile + '.astra'), ROOT / 'lib/astra/base/errors.astra']
		cflags = ['-DM17_VIRTUAL'] if profile == 'virtual' else []
		for level in ['O0', 'O1', 'O2']:
			obj, product = e.output / (profile + '-' + level + '.o'), e.output / (profile + '-' + level)
			e.run([e.compiler, '-' + level, '-c', *sources, *imports, '-o', obj])
			e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *cflags, obj, *providers, *flags, '-o', product])
			e.run([product], stdout=expected, timeout=15)
			e.files(obj, product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / (profile + '-O2')], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
		for sanitizer in ['address', 'thread']:
			instrument(e, profile, sources, providers, expected, sanitizer, [*flags, *cflags], vapis=vapis, entry_symbol='run_checked_frames')
		e.files(*sources)
	for name, body in [
		('unchecked-effect', 'var task=checked_task_in(frames,child());'),
		('nonnull-input', 'nonnull Cargo input=new(objects)Cargo();try{var task=checked_task_in(frames,take(move input));}catch(Error error){}'),
		('ordinary-move', 'var input=new(objects)Cargo();var task=take(move input);if(input==null){return 1;}'),
		('moved-context', 'var stolen=move frames;try{var task=checked_task_in(frames,child());}catch(Error error){}')]:
		negative = e.output / (name + '.astra')
		negative.write_text('[Allocator(kind="context",context="owned-concurrent")]class Cargo{}async void child(){}async void take(owned Cargo input){}int main(){var frames=concurrent_allocator(2,8192,1,64);var objects=concurrent_allocator(1,8192,7,64);' + body + 'return 0;}')
		e.run([e.compiler, '-c', negative, ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra', *imports, '-o', e.output / (name + '.o')], expected=1)
		e.files(negative)
	for name in ['task-core17.c', 'task-api17.c', 'worker17.c', 'virtual.h', 'provider.h']: e.files(ROOT / 'lib/runtime/async' / name)
	for name in ['context-17.c', 'context-17.h']: e.files(ROOT / 'lib/runtime/runtime' / name)
	e.files(*providers, *vapis, here / 'checked-frames.astra', Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
