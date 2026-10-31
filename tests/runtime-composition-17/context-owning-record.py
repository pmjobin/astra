#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Closed owning-record transport through ordinary native cleanup and contexts."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-owning-record')
	here = Path(__file__).resolve().parent
	source = here / 'context-owning-record.astra'
	mixed = here / 'context-owning-record-mixed.astra'
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-custom.vapi']
	imports = [argument for path in vapis for argument in ['--vapi', path]]
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'context-provider.c', here / 'context-owning-record-oracle.c']
	e.files(source, mixed, *vapis, *providers, Path(__file__))
	flags = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		flags += ['--link-object', obj]
		e.files(obj)
	expected = 'owning generic records: nested move/result/context field, independent origins and exact Class/handle cleanup\n'
	for fixture in [source, mixed]:
		name = fixture.stem
		for level in ['O0', 'O1', 'O2']:
			product = e.output / (name + '-' + level)
			e.run([e.compiler, '-' + level, fixture, *imports, *flags, '--link-library', 'pthread', '-o', product])
			e.run([product], stdout=expected, timeout=15)
			e.files(product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / (name + '-O2')], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=45)
		for sanitizer in ['address', 'thread']:
			instrument(e, name, [fixture], providers, expected, sanitizer, vapis=vapis)
	for name, text in {
		'historical-unqualified': 'class Item{}struct Box<T>{owned T item;}int main(){return 0;}',
		'missing-owned': 'struct Box<T> where T:Ownable{T item;}int main(){return 0;}',
		'wrong-bound': 'struct Box<T> where T:Numeric{T item;}int main(){return 0;}',
		'wrong-argument': 'struct Box<T> where T:Ownable{owned T item;}int main(){Box<int> value={item=17};return 0;}',
		'copy': source.read_text().replace('NestedOwnerRecord<RecordItem> second = move first;', 'NestedOwnerRecord<RecordItem> second = first;'),
		'double-move': source.read_text().replace('var host = new (context) RecordHost(move second);', 'var host = new (context) RecordHost(move second);NestedOwnerRecord<RecordItem> stale = move second;'),
	}.items():
		negative = e.output / (name + '.astra'); negative.write_text(text)
		diagnostic = {
			'historical-unqualified': 'owned struct fields are unsupported',
			'missing-owned': 'Ownable record parameters require explicit owned fields',
			'wrong-bound': 'where clauses on generic structs are unsupported',
			'wrong-argument': 'owning generic record argument requires its declared Ownable capability',
			'copy': 'owning record copy is forbidden',
			'double-move': 'use of moved owned value',
		}[name]
		e.run([e.compiler, '-c', negative, *imports, '-o', e.output / 'negative.o'], expected=1, contains=diagnostic)
		e.files(negative)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
