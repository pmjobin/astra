#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual replacement preserves cell generation, original context and retirement."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output, profile='heap'):
	assert profile in ['heap', 'selected', 'alternate', 'empty']
	e = Evidence(compiler, output, 'runtime-composition-17-mutable-scoped-fields-' + profile)
	here = Path(__file__).resolve().parent
	original = here / 'mutable-scoped-fields.astra'
	text = original.read_text()
	if profile == 'selected':
		text = text.replace('class MutableEnvelope {', '[Allocator(kind="context",context="scoped-affine")]class MutableEnvelope {')
		text = text.replace('new MutableEnvelope(move initial)', 'new(second) MutableEnvelope(move initial)')
		text = text.replace('scoped_allocator_query(second, 1) != 1', 'scoped_allocator_query(second, 1) != 2')
		text = text.replace('scoped_allocator_query(second, 1) != 0) { return 4;', 'scoped_allocator_query(second, 1) != 1) { return 4;')
	if profile == 'empty':
		text = text.replace('init(owned MutableLeaf input) { this.child = move input; }', 'init() { this.child = mutable_empty(); }')
		text = text.replace('var envelope = new MutableEnvelope(move initial);', 'var envelope = new MutableEnvelope(); envelope.replace(move initial);')
		text += '\nowned MutableLeaf mutable_empty() { return null; }\n'
	if profile == 'alternate': text = text.replace('mutable_case(true)', 'mutable_case(false)')
	source = e.output / 'mutation.astra'
	source.write_text(text)
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'mutable-scoped-fields-oracle.c']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	expected = 'scoped mutation: old generations retire once and replacements retain their exact contexts\n'
	for level in ['O0', 'O1', 'O2']:
		obj = e.output / ('mutation-' + level + '.o')
		product = obj.with_suffix('')
		e.run([e.compiler, '-' + level, '-c', source, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, '-o', product])
		e.run([product], stdout=expected)
		e.files(obj, product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	instrument(e, 'mutation', [source], providers, expected, 'address', vapis=[vapi], entry_symbol='mutable_probe')
	for name, changed, diagnostic in [
		('moved-input', text.replace('if (envelope.read() != 2', 'int stale = replacement.read(); if (envelope.read() != 2'), 'moved'),
		('retired-backing', text.replace('var last = new(first)', 'release first_backing; var last = new(first)'), 'exclusively borrowed'),
	]:
		assert changed != text
		negative = e.output / (name + '.astra')
		negative.write_text(changed)
		e.run([e.compiler, '--check', negative, '--vapi', vapi], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(original, source, Path(__file__), vapi, *providers, ROOT / 'lib/runtime/runtime/context-17.h', ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'tests/concurrency-runtime-13/sanitizers.py')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
