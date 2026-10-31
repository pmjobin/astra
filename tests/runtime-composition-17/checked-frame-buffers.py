#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise complete default/context buffer captures through checked admission."""
from pathlib import Path
import re
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def buffer_captures(text):
	old = 'owned ConcurrentAllocator token) throws Error {'
	assert text.count(old) == 2
	text = text.replace(old, 'owned ConcurrentAllocator token, owned u8[] plain, owned ContextBytes<ConcurrentAllocator> bytes) throws Error {')
	text = text.replace('checked_frame_event(1, cargo.id());', 'if (len(plain) != 17 || plain[0] != 37 || len(bytes) != 23 || bytes[0] != 41) { throw new Error("lost buffer capture"); }\n\tchecked_frame_event(1, cargo.id());')
	text = text.replace('move cargo, move token)', 'move cargo, move token, move plain, move bytes)')
	text = text.replace('move nested, move resource)', 'move nested, move resource, move plain, move bytes)')
	text = text.replace('move failing, move resource)', 'move failing, move resource, move plain, move bytes)')
	text = text.replace('move dropped, move resource)', 'move dropped, move resource, move plain, move bytes)')
	text = text.replace('var token = concurrent_allocator(1, 1024, 3, 64);', 'var token = concurrent_allocator(1, 1024, 3, 64);\n\tvar plain = new u8[17]; plain[0] = 37; var bytes = new(objects)u8[23]; bytes[0] = 41;')
	text = text.replace('var resource = concurrent_allocator(1, 1024, 3, 64);', 'var resource = concurrent_allocator(1, 1024, 3, 64);\n\t\tvar plain = new u8[17]; plain[0] = 37; var bytes = new(objects)u8[23]; bytes[0] = 41;')
	text = text.replace('!caught || cargo == null', '!caught || len(plain) != 17 || plain[0] != 37 || len(bytes) != 23 || bytes[0] != 41 || cargo == null')
	text = text.replace('cargo != null || token != null', 'len(plain) != 0 || len(bytes) != 0 || cargo != null || token != null')
	text = text.replace('dropped != null || resource != null', 'len(plain) != 0 || len(bytes) != 0 || dropped != null || resource != null')
	text = text.replace('!failed || failing != null', '!failed || len(plain) != 0 || len(bytes) != 0 || failing != null')
	start = text.index('export(C) int run_checked_frames()')
	end = text.index('\t{\n\t\tvar dropped', start)
	initial = re.sub(r'\bplain\b', 'first_plain', text[start:end])
	initial = re.sub(r'\bbytes\b', 'first_bytes', initial)
	text = text[:start] + initial + text[end:]
	return text


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-checked-frame-buffers')
	here = Path(__file__).resolve().parent
	text = buffer_captures((here / 'checked-frames.astra').read_text())
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'checked-frames-oracle.c']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi']
	imports = [arg for path in vapis for arg in ['--vapi', path]]
	flags = ['-Wl,--wrap=astra_async_try_new_allocated', '-Wl,--wrap=calloc']
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
	e.files(*providers, *vapis, here / 'checked-frames.astra', Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
