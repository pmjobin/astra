#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe actual caller ownership on refusal and checked constructor rollback."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output, profile='direct'):
	assert profile in ['direct', 'selected']
	e = Evidence(compiler, output, 'runtime-composition-17-fallible-records-' + profile)
	here = Path(__file__).resolve().parent
	sources = [here / 'context-fallible-records.astra']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/platform/text-posix.c', here / 'context-fallible-inputs-oracle.c']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-fallible-inputs.vapi']
	if profile == 'selected':
		variant = e.output / 'selected-records.astra'; text = sources[0].read_text()
		text = text.replace('class AdmissionChild {', '[Allocator(kind="context",context="owned-concurrent")]\nclass AdmissionChild {')
		text = text.replace('new AdmissionChild(', 'new(objects) AdmissionChild(')
		variant.write_text(text); sources = [variant]
	imports = [argument for path in vapis for argument in ['--vapi', path]]
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]; e.files(obj)
	expected = 'fallible inputs: refusal preserves caller owners, admission empties slots and rollback retires each input once\n'
	for level in ['0', '1', '2']:
		product = e.output / ('inputs-O' + level)
		e.run([e.compiler, '-O' + level, *sources, *imports, *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout=expected)
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'inputs-O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors')
	for sanitizer in ['address', 'thread']: instrument(e, 'inputs', sources, providers, expected, sanitizer, vapis=vapis)
	template = sources[0].read_text()
	for name, text, diagnostic in [
		('ordinary-new-still-consumes', template.replace('var first = try_new(context)', 'var first = new(context)'), 'moved'),
		('copied-record', template.replace('AdmissionOwner(move first_record,', 'AdmissionOwner(first_record,'), 'MOVE_VALUE argument requires an explicit move'),
		('duplicate-record', template.replace('int main()', 'void pair(AdmissionEnvelope<AdmissionChild> first,AdmissionEnvelope<AdmissionChild> second){}\nint main()').replace('var first_tail =', 'pair(move first_record,move first_record);var first_tail ='), 'duplicate record MOVE_VALUE argument'),
		('unnamed-record', template.replace('AdmissionOwner(move first_record,', 'AdmissionOwner(admission_record(objects,1),'), 'MOVE_VALUE argument requires an explicit move')]:
		negative = e.output / (name + '.astra'); negative.write_text(text)
		e.run([e.compiler, '-c', negative, *imports, '-o', negative.with_suffix('.o')], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(*sources, *providers, *vapis, Path(__file__))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
