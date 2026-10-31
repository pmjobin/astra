#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public typed ownership handoff, real worker computation and file completion."""
from pathlib import Path
import json
import struct
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, prefix, output):
	e = Evidence(compiler, output, 'runtime-composition-17-public-bridge')
	prefix = Path(prefix).resolve()
	here = Path(__file__).resolve().parent
	input_path, output_path = e.output / 'input.bin', e.output / 'output.bin'
	data = bytes((i * 17 + 53) % 256 for i in range(67))
	input_path.write_bytes(data)
	values = []
	for seed, inputs in [(17, data), (29, data[::-1])]:
		value = seed
		for i in range(1000003): value = (value * 17 + inputs[i % 67] + i % 251) % 65521
		values.append(value)
	expected_file = struct.pack('<ii', *values)
	e.data['independent_results'] = values
	e.save()
	source = e.output / 'public.astra'
	source.write_text((here / 'bridge-public.astra').read_text().replace('INPUT_PATH', json.dumps(str(input_path))).replace('OUTPUT_PATH', json.dumps(str(output_path))))
	sources = [here / 'bridge-common.astra', here / 'bridge-worker.astra', source, ROOT / 'lib/astra/base/errors.astra', ROOT / 'lib/astra/async/payload.astra']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', ROOT / 'lib/bindings/async/composition.vapi', ROOT / 'lib/bindings/async/payload.vapi']
	imports = [argument for path in vapis for argument in ['--vapi', path]]
	providers = [ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/async/linux.c', ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'bridge-public-oracle.c']
	flags = ['-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', '-isystem', prefix / 'include', prefix / 'lib/liburing.a', '-Wl,--wrap=astra_async_worker_pool_close']
	expected = 'public bridge: Astra owning buffers and contexts round-trip through two workers and real overlapping file completions; all joined\n'
	for level in ['O0', 'O1', 'O2']:
		obj, product = e.output / ('bridge-' + level + '.o'), e.output / ('bridge-' + level)
		e.run([e.compiler, '-' + level, '-c', *sources, *imports, '-o', obj])
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, here / 'bridge-public-entry.c', *flags, '-o', product])
		e.run([product], stdout=expected, timeout=30)
		assert output_path.read_bytes() == expected_file
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'bridge-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=90)
	assert output_path.read_bytes() == expected_file
	for sanitizer in ['address', 'thread']:
		instrument(e, 'bridge', sources, providers, expected, sanitizer, flags, vapis=vapis)
		assert output_path.read_bytes() == expected_file
	trace = e.output / 'kernel.strace'
	e.run(['strace', '-f', '-o', trace, '-e', 'trace=io_uring_setup,io_uring_enter,io_uring_register,eventfd2,poll,clone,clone3', e.output / 'bridge-O2'], stdout=expected, timeout=30)
	assert output_path.read_bytes() == expected_file
	text = trace.read_text()
	for operation in ['IORING_SETUP_SINGLE_ISSUER', 'IORING_SETUP_CQSIZE', 'IORING_SETUP_NO_SQARRAY', 'io_uring_enter(', 'eventfd2(', 'poll(']: assert operation in text, operation
	# New source controls preserve the old nomination refusal and reject
	# missing observation authority before any native execution.
	legacy = e.output / 'legacy-nomination.astra'
	legacy.write_text((here / 'bridge-common.astra').read_text().replace('linux-io-uring-composed', 'linux-io-uring'))
	e.run([e.compiler, '-c', legacy, *sources[1:], *imports, '-o', e.output / 'negative.o'], expected=1, contains='source runtime nominations require the same provider and nominal error type')
	wrong = e.output / 'wrong-pool.vapi'
	wrong.write_text(vapis[1].read_text().replace('astra_async_worker_pool_close', 'unrelated_resource_close'))
	wrong_imports = [argument for path in [vapis[0], wrong, vapis[2]] for argument in ['--vapi', path]]
	e.run([e.compiler, '-c', *sources, *wrong_imports, '-o', e.output / 'negative.o'], expected=1, contains='exact WorkerPool close contract')
	moved = e.output / 'moved-pool.astra'
	moved.write_text('void consume_pool(owned WorkerPool pool){}\n' + source.read_text().replace('\tvar background = side_read(move side);', '\tconsume_pool(move pool);\n\tvar background = side_read(move side);'))
	e.run([e.compiler, '-c', sources[0], sources[1], moved, *sources[3:], *imports, '-o', e.output / 'negative.o'], expected=1)
	unbridged = e.output / 'unbridged.astra'
	needle = 'await pool.submit(task_in(frames, CPU.batch(move inner, move one, move two)))'
	assert source.read_text().count(needle) == 1
	unbridged.write_text(source.read_text().replace(needle, 'await task_in(frames, CPU.batch(move inner, move one, move two))'))
	e.run([e.compiler, '-c', sources[0], sources[1], unbridged, *sources[3:], *imports, '-o', e.output / 'negative.o'], expected=1, contains='explicit composed provider contract')
	e.files(legacy, wrong, moved, unbridged)
	e.files(*sources, *providers, *vapis, here / 'bridge-public-entry.c', here / 'bridge-public.astra', input_path, output_path, trace, prefix / 'lib/liburing.a', Path(__file__))
	for name in ['virtual.h', 'provider.h', 'linux.h', 'task-core17.c', 'task-api17.c', 'worker17.c']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
