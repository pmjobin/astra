#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute fallible owner admission/refusal in scope-sensitive lifetime bodies."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-fallible-lifetimes')
	source = Path(__file__).with_suffix('.astra')
	api = ROOT / 'lib/bindings/memory/contexts.vapi'
	provider = ROOT / 'lib/runtime/runtime/context-17.c'
	runtime = e.output / 'context17.o'
	e.files(source, api, provider, provider.with_suffix('.h'), Path(__file__), ROOT / 'tests/systems-dsp-9/support.py')
	e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', runtime])
	text = source.read_text()
	generic = text.replace('class FallibleLifetimeHost {', 'class GenericCarrier<T> {').replace('owned FallibleScopedLeaf scoped', 'owned T scoped').replace(')FallibleLifetimeHost(', ')GenericCarrier<FallibleScopedLeaf>(')
	inner = 'class InnerValue { private int value; init(int value){this.value=value;} int read(){return this.value;} }\n'
	deep = text.replace('class FalliblePlainLeaf {', inner + 'class FalliblePlainLeaf {')
	start = deep.index('class FalliblePlainLeaf {')
	end = deep.index('[Allocator(kind="context",context="owned-concurrent")]', start)
	deep = deep[:start] + 'class FalliblePlainLeaf { private owned InnerValue inner; init(int value){var item=new InnerValue(value);this.inner=move item;} int read(){return this.inner.read();} }\n' + deep[end:]
	for profile, contents in [('ordinary', text), ('generic', generic), ('deep', deep)]:
		selected = source
		if profile != 'ordinary':
			selected = e.output / (profile + '.astra')
			selected.write_text(contents)
			e.files(selected)
		for level in ['0', '1', '2']:
			product = e.output / (profile + '-O' + level)
			e.run([e.compiler, '-O' + level, selected, '--vapi', api, '--link-object', runtime, '--link-library', 'pthread', '-o', product])
			e.run([product], stdout='', timeout=10)
			e.files(product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / (profile + '-O2')], stdout='', contains='ERROR SUMMARY: 0 errors')

	e.files(runtime)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
