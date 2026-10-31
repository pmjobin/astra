#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual scoped owning record results across typed task observation."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output, profile='flat'):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-task-results-' + profile)
	here = Path(__file__).resolve().parent
	original = here / 'scoped-task-results.astra'
	text = original.read_text()
	link_flags = []
	if profile in ['empty', 'single-empty']:
		start = text.index('async ScopedResultPacket scoped_result_deliver(')
		end = text.index('void scoped_result_inspect(', start)
		text = text[:start] + '''async ScopedResultPacket scoped_result_deliver(ScopedResultPacket input, int mode) throws Error {
	await delay_ticks(1);
	if (mode == 1) { throw new Error("scoped result failure"); }
	scoped_result_ready(mode);
	ScopedResultPacket vacant = { first = scoped_result_empty(), second = scoped_result_empty(), marker = 17 };
	return move vacant;
}
''' + text[end:]
		link_flags = ['-DSCOPED_RESULT_EMPTY=1']
		if profile == 'single-empty':
			text = text.replace('struct ScopedResultPacket { owned ScopedResultLeaf first; owned ScopedResultLeaf second; int marker; }', 'struct ScopedResultPacket { owned ScopedResultLeaf first; }')
			text = text.replace('{ first = scoped_result_empty(), second = scoped_result_empty(), marker = 17 }', '{ first = scoped_result_empty() }')
			text = text.replace('{ first = move left, second = move right, marker = 17 }', '{ first = move left }')
			start = text.index('void scoped_result_inspect(')
			end = text.index('void scoped_result_drop(', start)
			text = text[:start] + '''void scoped_result_inspect(borrowed ScopedResultPacket input) {
	if (input.first == null) { scoped_result_observed(0, 0, 17); }
	else { scoped_result_observed(input.first.read(), 0, 17); }
}
''' + text[end:]
			link_flags.append('-DSCOPED_RESULT_SINGLE=1')
	elif profile == 'generic':
		text = text.replace('struct ScopedResultPacket { owned ScopedResultLeaf first; owned ScopedResultLeaf second; int marker; }', 'struct ScopedResultPacket<T> where T:Ownable { owned T first; owned T second; int marker; }')
		text = text.replace('ScopedResultPacket input', 'ScopedResultPacket<ScopedResultLeaf> input')
		text = text.replace('ScopedResultPacket vacant', 'ScopedResultPacket<ScopedResultLeaf> vacant')
		text = text.replace('async ScopedResultPacket ', 'async ScopedResultPacket<ScopedResultLeaf> ')
	elif profile == 'nested':
		text = text.replace('struct ScopedResultPacket { owned ScopedResultLeaf first; owned ScopedResultLeaf second; int marker; }', 'struct ScopedResultInner { owned ScopedResultLeaf first; owned ScopedResultLeaf second; }\nstruct ScopedResultPacket { ScopedResultInner inner; int marker; }')
		text = text.replace('input.first.read()', 'input.inner.first.read()').replace('input.second.read()', 'input.inner.second.read()')
		text = text.replace('{ first = move left, second = move right, marker = 17 }', '{ inner = { first = move left, second = move right }, marker = 17 }')
		text = text.replace('{ first = scoped_result_empty(), second = scoped_result_empty(), marker = 17 }', '{ inner = { first = scoped_result_empty(), second = scoped_result_empty() }, marker = 17 }')
		text = text.replace('input.first == null', 'input.inner.first == null').replace('input.second == null', 'input.inner.second == null')
	else:
		assert profile == 'flat'
	source = e.output / (profile + '.astra')
	source.write_text(text)
	sources = [source, ROOT / 'lib/astra/async/virtual.astra', ROOT / 'lib/astra/base/errors.astra']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/virtual.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'scoped-task-results-oracle.c']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	expected = 'scoped results: exact observed owners, error, cancellation and cold discard\n'
	for level in ['O0', 'O1', 'O2']:
		obj = e.output / (profile + '-' + level + '.o')
		product = obj.with_suffix('')
		e.run([e.compiler, '-' + level, '-c', *sources, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *link_flags, obj, *providers, '-o', product])
		e.run([product], stdout=expected)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	instrument(e, profile, sources, providers, expected, 'address', link_flags=link_flags, vapis=[vapi], entry_symbol='scoped_result_probe')
	for name, changed, diagnostic in [
		('moved-result', text.replace('scoped_result_inspect(result);', 'var duplicate = scoped_result_deliver(move result, 0); scoped_result_inspect(result);'), 'moved'),
		('retired-backing', text.replace('for (int mode = 0;', 'release first_backing; for (int mode = 0;'), 'exclusively borrowed'),
		('nonvoid-root', text.replace('var discarded = scoped_result_discard(move input);', 'var discarded = scoped_result_deliver(move input, 0);'), 'sole void root'),
	]:
		assert changed != text
		negative = e.output / (name + '.astra')
		negative.write_text(changed)
		e.run([e.compiler, '--check', negative, *sources[1:], '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(original, Path(__file__), vapi, *sources, *providers, ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py', ROOT / 'lib/runtime/runtime/context-17.h')
	for name in ['virtual.h', 'provider.h', 'task-core17.c', 'task-api17.c']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
