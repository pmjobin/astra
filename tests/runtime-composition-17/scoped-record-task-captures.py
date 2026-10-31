#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Two exact scoped backing instances retained through plain/generic task captures."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-record-task-captures')
	here = Path(__file__).resolve().parent
	sources = [here / 'scoped-record-task-captures.astra', ROOT / 'lib/astra/async/virtual.astra', ROOT / 'lib/astra/base/errors.astra']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/virtual.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'scoped-record-task-captures-oracle.c']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	expected = 'scoped record: two retained owners, two allocator instances, exact joined retirement\n'
	for profile in ['record', 'generic']:
		text = sources[0].read_text()
		if profile == 'generic':
			text = text.replace('struct ScopedTaskBundle { owned ScopedTaskInput first; owned ScopedTaskInput second; int marker; }', 'struct ScopedTaskBundle<T> where T:Ownable { owned T first; owned T second; int marker; }')
			text = text.replace('ScopedTaskBundle input', 'ScopedTaskBundle<ScopedTaskInput> input')
			assert 'ScopedTaskBundle<ScopedTaskInput> input' in text
		source = e.output / (profile + '.astra')
		source.write_text(text)
		for level in ['O0', 'O1', 'O2']:
			obj = e.output / (profile + '-' + level + '.o')
			product = obj.with_suffix('')
			e.run([e.compiler, '-' + level, '-c', source, *sources[1:], '--vapi', vapi, '-o', obj])
			e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, '-o', product])
			e.run([product], stdout=expected)
			e.files(obj, product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors')
		instrument(e, profile, [source, *sources[1:]], providers, expected, 'address', vapis=[vapi], entry_symbol='scoped_record_probe')
		e.files(source)
	e.files(*sources, vapi, *providers, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py', ROOT / 'lib/runtime/runtime/context-17.h')
	for name in ['virtual.h', 'provider.h', 'task-core17.c', 'task-api17.c']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
