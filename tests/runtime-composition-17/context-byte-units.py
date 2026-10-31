#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Opaque native units retain context-byte result, borrow and field ownership."""
from pathlib import Path
import itertools
import re
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-byte-sdk')
	here = Path(__file__).resolve().parent
	fixture = here / 'context-bytes.astra'; text = fixture.read_text()
	entry = text.index('export(C) int context_bytes_run()')
	leaf, middle, consumer = [e.output / (name + '.astra') for name in ['leaf', 'middle', 'consumer']]
	leaf.write_text('namespace ByteLeaf;\n' + text[:entry])
	middle.write_text('namespace ByteMiddle;\nowned ContextBytes<ConcurrentAllocator> relay(int count){var bytes=ByteLeaf.make_context_bytes(count);return move bytes;}\n')
	client = text[entry:].replace('make_context_bytes(', 'ByteMiddle.relay(').replace('inspect_bytes(', 'ByteLeaf.inspect_bytes(')
	for name in ['ByteEnvelope', 'ByteRecord']: client = re.sub(r'\b' + name + r'\b', 'ByteLeaf.' + name, client)
	consumer.write_text('extern(C) int context_bytes_finish();\n' + client)
	contexts = ROOT / 'lib/bindings/memory/contexts.vapi'; custom = here / 'context-custom.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'context-provider.c', here / 'context-bytes-oracle.c']
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_context17_allocate_mode', 'astra_context17_release_origin_checked']]
	e.files(fixture, leaf, middle, consumer, contexts, custom, *providers, here / 'context-provider.h', Path(__file__))
	objects = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		objects.append(obj); e.files(obj)
	selectors = ['ByteLeaf.ByteEnvelope', 'ByteLeaf.ByteRecord<ConcurrentAllocator>', 'ByteLeaf.make_context_bytes', 'ByteLeaf.inspect_bytes']
	exports = [arg for name in selectors for arg in ['--native-export', name]]
	expected = 'context bytes: actual independent backing, zeroing, result/field/record moves and original release\n'
	for levels in [*itertools.product('02', repeat=3), ('1', '1', '1')]:
		case = e.output / ('units-' + ''.join(levels)); case.mkdir(exist_ok=True)
		e.run([e.compiler, '-O' + levels[0], '-c', leaf, '--vapi', contexts, '--vapi', custom, '--module', 'ByteLeaf', *exports, '--emit-interface', case / 'leaf.asti', '-o', case / 'leaf.o'])
		e.run([e.compiler, '-O' + levels[1], '-c', middle, '--vapi', contexts, '--module', 'ByteMiddle', '--native-export', 'ByteMiddle.relay', '--import-module', case / 'leaf.asti', '--emit-interface', case / 'middle.asti', '-o', case / 'middle.o'])
		sdk = case / 'sdk'; sdk.mkdir(exist_ok=True)
		for path in [*[case / name for name in ['leaf.asti', 'leaf.o', 'middle.asti', 'middle.o']], contexts, *objects]: shutil.copyfile(path, sdk / path.name)
		shutil.copyfile(e.compiler, sdk / 'astrac'); (sdk / 'astrac').chmod(0o755)
		shutil.copyfile(consumer, sdk / 'consumer.astra')
		assert sorted(p.name for p in sdk.glob('*.astra')) == ['consumer.astra']
		assert 'CONTEXT-BYTES' in (sdk / 'leaf.asti').read_text()
		command = [sdk / 'astrac', '-O' + levels[2], '-c', sdk / 'consumer.astra', '--vapi', sdk / contexts.name, '--import-module', sdk / 'middle.asti', '-o', sdk / 'consumer.o']
		e.run(command, cwd=sdk)
		e.run(['cc', '-pthread', sdk / 'consumer.o', sdk / 'leaf.o', sdk / 'middle.o', *[sdk / p.name for p in objects], *wrappers, '-o', sdk / 'consumer'], cwd=sdk)
		e.run([sdk / 'consumer'], stdout=expected, cwd=sdk)
		if levels == ('2', '2', '2'):
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout=expected, contains='ERROR SUMMARY: 0 errors', cwd=sdk)
			trace = sdk / 'opens.log'; e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
			assert str(leaf) not in trace.read_text() and str(middle) not in trace.read_text()
		e.files(*[p for p in sdk.iterdir() if p.is_file()])
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
