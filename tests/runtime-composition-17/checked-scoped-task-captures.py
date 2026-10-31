#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Refused scoped capture, original-input reuse and checked admitted retirement."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output, profile='class'):
	assert profile in ['class', 'records', 'generic-records', 'fieldless']
	name = 'runtime-composition-17-checked-scoped-' + ('generic-record-captures' if profile == 'generic-records' else 'record-captures' if profile == 'records' else 'fieldless-captures' if profile == 'fieldless' else 'task-captures')
	e = Evidence(compiler, output, name)
	here = Path(__file__).resolve().parent
	sources = [here / ('checked-scoped-record-captures.astra' if profile in ['records', 'generic-records'] else 'checked-scoped-task-captures.astra'), ROOT / 'lib/astra/async/virtual.astra', ROOT / 'lib/astra/base/errors.astra']
	providers = [here / 'checked-scoped-task-captures-oracle.c', ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/virtual.c', ROOT / 'lib/runtime/platform/text-posix.c']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	flags = ['-DM17_SCOPED_RECORD'] if profile in ['records', 'generic-records'] else []
	if profile == 'generic-records':
		original = sources[0]
		variant = e.output / 'generic-records.astra'
		text = original.read_text().replace('struct CheckedScopedPacket { owned CheckedScopedInput first; owned CheckedScopedInput second; int marker; }', 'struct CheckedScopedPacket<T> where T:Ownable { owned T first; owned T second; int marker; }')
		text = text.replace('CheckedScopedPacket input', 'CheckedScopedPacket<CheckedScopedInput> input')
		assert 'CheckedScopedPacket<CheckedScopedInput> input' in text
		variant.write_text(text)
		e.files(original)
		sources[0] = variant
	if profile == 'fieldless':
		original = sources[0]
		variant = e.output / 'fieldless.astra'
		prefix = '[ExceptionRoot]class EmptyFrameFault{init(string message){}virtual property string message{get{return "frame";}}}enum RunStatus{Completed,Cancelled}async runtime VirtualExecutor throws EmptyFrameFault returns RunStatus;'
		variant.write_text(prefix + original.read_text().replace('throws Error', 'throws EmptyFrameFault').replace('catch (Error error)', 'catch (EmptyFrameFault error)'))
		e.files(original)
		sources = [variant]

	expected = ''.join('checked scoped ' + kind + ': refused capture preserved, admitted capture moved, original owner retired once\n' for kind in ['region', 'pool'])
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *flags, '-c', provider, '-o', obj])
		links.append(obj)
		e.files(obj)
	for level in ['O0', 'O1', 'O2']:
		obj = e.output / (level + '.o')
		product = obj.with_suffix('')
		e.run([e.compiler, '-' + level, '-c', *sources, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-pthread', obj, *links, '-o', product])
		e.run([product], stdout=expected)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	instrument(e, 'checked-scoped', sources, providers, expected, 'address', flags, vapis=[vapi], entry_symbol='checked_scope_run')
	e.files(*sources, *providers, vapi, Path(__file__), ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py', ROOT / 'lib/runtime/runtime/context-17.h')
	for name in ['virtual.h', 'provider.h', 'task-core17.c', 'task-api17.c']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
