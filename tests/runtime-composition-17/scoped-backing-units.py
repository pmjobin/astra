#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Opaque units preserve scoped controller borrows and owned backing inputs."""
from pathlib import Path
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-scoped-backing-units')
	here = Path(__file__).resolve().parent
	fixture = here / 'scoped-backing.astra'
	text = fixture.read_text()
	helpers, _ = text.split('export(C) int scoped_backing_run()', 1)
	producer = 'namespace ScopedBacking;\n' + helpers
	for name, type_name in [('consume_default', 'u8[]'), ('consume_contextual', 'ContextBytes<ConcurrentAllocator>')]:
		producer += '''
int NAME(owned TYPE backing, int kind, int slots, int id) {
	{
		var context = scoped_allocator<ScopedAllocator>(backing, kind, slots);
		if (id == 3) { if (context != null) { return 1; } return 0; }
		if (context == null || inspect_scoped(context, id) != 0) { return 2; }
	}
	if (changed_bytes(backing) < 3) { return 3; }
	return 0;
}
'''.replace('NAME', name).replace('TYPE', type_name)
	consumer = '''
[CCode(buffer_abi="u8-i32")]extern(C) void scoped_backing_remember(borrowed u8[] bytes, int id);
extern(C) int scoped_backing_finish();
export(C) int scoped_backing_run() {
	{
		owned u8[] first = new u8[8197];
		var parent = concurrent_allocator(0, 0, 7, 64);
		var second = new(parent) u8[12341];
		scoped_backing_remember(first, 1); scoped_backing_remember(second, 2);
		{
			var context = scoped_allocator<ScopedAllocator>(first, 1, 7);
			if (context == null || ScopedBacking.inspect_scoped(context, 1) != 0) { return 1; }
		}
		if (ScopedBacking.changed_bytes(first) < 3) { return 2; }
		if (ScopedBacking.consume_contextual(move second, 2, 5, 2) != 0) { return 3; }
	}
	{
		owned u8[] empty = new u8[0]; scoped_backing_remember(empty, 3);
		if (ScopedBacking.consume_default(move empty, 1, 3, 3) != 0) { return 4; }
	}
	return scoped_backing_finish();
}
'''
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'scoped-backing.vapi']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'scoped-backing-oracle.c']
	flags = ['-Wl,--wrap=' + name for name in ['astra_context17_open_scoped', 'astra_context17_destroy', 'astra_context17_release_origin_checked', 'free']]
	objects = []
	for source in providers:
		obj = e.output / (source.stem + '.o'); objects.append(obj)
		e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', source, '-o', obj]); e.files(obj)
	exports = [arg for name in ['inspect_scoped', 'changed_bytes', 'consume_default', 'consume_contextual'] for arg in ['--native-export', 'ScopedBacking.' + name]]
	expected = 'scoped backing: exact caller buffers, exclusive lexical loans, original storage and ordered retirement\n'
	for levels in ['00', '02', '20', '22', '11']:
		case = e.output / ('units-' + levels); case.mkdir(exist_ok=True)
		source = case / 'implementation.astra'; source.write_text(producer)
		e.run([e.compiler, '-O' + levels[0], '-c', source, *[arg for p in vapis for arg in ['--vapi', p]], '--module', 'ScopedBacking', *exports, '--emit-interface', case / 'producer.asti', '-o', case / 'producer.o'])
		sdk = case / 'sdk'; sdk.mkdir(exist_ok=True)
		for path in [case / 'producer.asti', case / 'producer.o', *vapis, *objects]: shutil.copyfile(path, sdk / path.name)
		shutil.copyfile(e.compiler, sdk / 'astrac'); (sdk / 'astrac').chmod(0o755)
		(sdk / 'consumer.astra').write_text(consumer)
		assert [p.name for p in sdk.glob('*.astra')] == ['consumer.astra']
		command = [sdk / 'astrac', '-O' + levels[1], '-c', sdk / 'consumer.astra', *[arg for p in vapis for arg in ['--vapi', sdk / p.name]], '--import-module', sdk / 'producer.asti', '-o', sdk / 'consumer.o']
		e.run(command, cwd=sdk)
		e.run(['cc', '-pthread', sdk / 'consumer.o', sdk / 'producer.o', *[sdk / p.name for p in objects], *flags, '-o', sdk / 'consumer'], cwd=sdk)
		e.run([sdk / 'consumer'], stdout=expected, cwd=sdk)
		if levels == '22':
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout=expected, contains='ERROR SUMMARY: 0 errors', cwd=sdk)
			trace = sdk / 'opens.log'; e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
			assert str(source) not in trace.read_text() and str(sdk / 'producer.asti') in trace.read_text()
		e.files(source, *[p for p in sdk.iterdir() if p.is_file()])
	e.files(fixture, *vapis, *providers, Path(__file__)); e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
