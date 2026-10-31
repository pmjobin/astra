#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual public scoped owners retained by cold and suspended task frames."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-task-captures')
	here = Path(__file__).resolve().parent
	sources = [here / 'scoped-task-captures.astra', ROOT / 'lib/astra/async/virtual.astra', ROOT / 'lib/astra/base/errors.astra']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [here / 'scoped-task-captures-oracle.c', ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/virtual.c', ROOT / 'lib/runtime/platform/text-posix.c']
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links.append(obj)
		e.files(obj)
	expected = 'scoped task captures: cold drop, delayed run, child handoff, error and cancellation retire original owners once\n'
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('scoped-captures-' + level)
		obj = product.with_suffix('.o')
		e.run([e.compiler, '-' + level, '-c', *sources, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-pthread', obj, *links, '-o', product])
		e.run([product], stdout=expected)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'scoped-captures-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
	instrument(e, 'scoped-captures', sources, providers, expected, 'address', vapis=[vapi], entry_symbol='scoped_task_captures_run')
	for name, text, runtime, diagnostic in [
		('moved-input', sources[0].read_text().replace('var task = scoped_task_idle(move input);', 'var task = scoped_task_idle(move input); release input;'), sources[1], 'moved'),
		('retired-backing', sources[0].read_text().replace('if (objects == null)', 'release backing; if (objects == null)'), sources[1], 'exclusively borrowed'),
		('worker-capture', sources[0].read_text().split('int scoped_capture_cold')[0] + 'int main(){return 0;}', ROOT / 'lib/astra/async/threaded.astra', 'threaded task parameter is not Send'),
	]:
		negative = e.output / (name + '.astra')
		negative.write_text(text)
		e.run([e.compiler, '--check', negative, runtime, sources[2], '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative, runtime)
	e.files(*sources, vapi, *providers, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py')
	e.files(ROOT / 'tests/concurrency-runtime-13/sanitizers.py', ROOT / 'lib/runtime/runtime/context-17.h')
	for name in ['virtual.h', 'provider.h', 'task-core17.c', 'task-api17.c']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
