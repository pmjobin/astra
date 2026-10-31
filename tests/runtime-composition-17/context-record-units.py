#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Opaque native SDK for nested owning-record results and context-backed fields."""
from pathlib import Path
import hashlib
import itertools
import re
import runpy
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output, profile='base'):
	assert profile in ['base', 'mixed']
	e = Evidence(compiler, output, 'runtime-composition-17-record-sdk-' + profile)
	here = Path(__file__).resolve().parent
	fixture = here / ('context-owning-record' + ('-mixed' if profile == 'mixed' else '') + '.astra')
	text = fixture.read_text()
	leaf, middle, consumer = [e.output / (name + '.astra') for name in ['leaf', 'middle', 'consumer']]
	leaf.write_text('namespace RecordLeaf;\n' + text[:text.index('int main()')])
	nested = 'WrappedRecord' if profile == 'mixed' else 'NestedOwnerRecord'
	middle.write_text('namespace RecordMiddle;\nRecordLeaf.' + nested + '<RecordLeaf.RecordItem> relay(int identity){return RecordLeaf.create_owned_record(identity);}\n')
	client = text[text.index('int main()'):]
	client = client.replace('create_owned_record(17)', 'RecordMiddle.relay(17)')
	for name in ['NestedOwnerRecord', 'OwnerRecord', 'WrappedRecord', 'MixedRecord', 'CopyRecord', 'RecordItem', 'RecordHost']:
		client = re.sub(r'\b' + name + r'\b', 'RecordLeaf.' + name, client)
	if profile == 'mixed': client = client.replace('inspect(allocator)', 'RecordLeaf.inspect(allocator)')
	consumer.write_text('extern(C) int owning_record_finish();\n' + client)
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', here / 'context-custom.vapi']
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'context-provider.c', here / 'context-owning-record-oracle.c']
	e.files(fixture, leaf, middle, consumer, *vapis, *providers, Path(__file__))
	helper = ROOT / 'tests/structural-generics-15/units.py'
	metadata = runpy.run_path(str(helper)); e.files(helper)
	objects = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		objects.append(obj); e.files(obj)
	imports = [arg for path in vapis for arg in ['--vapi', path]]
	selectors = ['RecordLeaf.RecordItem', 'RecordLeaf.RecordHost', 'RecordLeaf.OwnerRecord<RecordLeaf.RecordItem>',
		'RecordLeaf.NestedOwnerRecord<RecordLeaf.RecordItem>', 'RecordLeaf.OwnerRecord<ConcurrentAllocator>', 'RecordLeaf.create_owned_record']
	if profile == 'mixed':
		selectors = ['RecordLeaf.RecordItem', 'RecordLeaf.RecordHost', 'RecordLeaf.CopyRecord<int>',
			'RecordLeaf.MixedRecord<RecordLeaf.RecordItem,RecordLeaf.CopyRecord<int>>', 'RecordLeaf.WrappedRecord<RecordLeaf.RecordItem>',
			'RecordLeaf.MixedRecord<ConcurrentAllocator,int>', 'RecordLeaf.create_owned_record', 'RecordLeaf.inspect']
	exports = [arg for name in selectors for arg in ['--native-export', name]]
	expected = 'owning generic records: nested move/result/context field, independent origins and exact Class/handle cleanup\n'
	for levels in [*itertools.product('02', repeat=3), ('1', '1', '1')]:
		case = e.output / ('units-' + ''.join(levels)); case.mkdir(exist_ok=True)
		e.run([e.compiler, '-O' + levels[0], '-c', leaf, *imports, '--module', 'RecordLeaf', *exports, '--emit-interface', case / 'leaf.asti', '-o', case / 'leaf.o'])
		e.run([e.compiler, '-O' + levels[1], '-c', middle, *imports, '--module', 'RecordMiddle', '--native-export', 'RecordMiddle.relay', '--import-module', case / 'leaf.asti', '--emit-interface', case / 'middle.asti', '-o', case / 'middle.o'])
		sdk = case / 'sdk'; sdk.mkdir(exist_ok=True)
		for path in [*[case / name for name in ['leaf.asti', 'leaf.o', 'middle.asti', 'middle.o']], *vapis, *objects]: shutil.copyfile(path, sdk / path.name)
		shutil.copyfile(e.compiler, sdk / 'astrac'); (sdk / 'astrac').chmod(0o755)
		shutil.copyfile(consumer, sdk / 'consumer.astra')
		assert sorted(p.name for p in sdk.glob('*.astra')) == ['consumer.astra']
		assert 'Ownable' in (sdk / 'leaf.asti').read_text()
		links = [arg for obj in objects for arg in ['--link-object', sdk / obj.name]]
		public = [arg for path in vapis for arg in ['--vapi', sdk / path.name]]
		command = [sdk / 'astrac', '-O' + levels[2], sdk / 'consumer.astra', *public, '--import-module', sdk / 'middle.asti', *links, '--link-library', 'pthread', '-o', sdk / 'consumer']
		e.run(command, cwd=sdk)
		e.run([sdk / 'consumer'], stdout=expected, cwd=sdk)
		if levels == ('2', '2', '2'):
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout=expected, contains='ERROR SUMMARY: 0 errors', cwd=sdk)
			trace = sdk / 'opens.log'
			e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
			opened = trace.read_text()
			assert str(leaf) not in opened and str(middle) not in opened
			e.files(trace)
			# An omitted current edge marker retains strict schema/compiler checks.
			# This does not authorize the separate unchanged-legacy ABI path.
			control = sdk / 'strict-default'; control.mkdir(exist_ok=True)
			for path in sdk.iterdir():
				if path.is_file(): shutil.copy2(path, control / path.name)
			original = (control / 'middle.asti').read_text()
			groups = metadata['metadata'](original)
			old_identity = groups['abi']['identity']
			groups['dependency RecordLeaf'].pop('compatibility')
			identity = metadata['fingerprint'](groups, False)
			# The ABI digest includes the exact field inventory. Rebind the
			# object symbols as well, preserving all ordinary identity checks.
			renames = []
			for group, values in groups.items():
				if (group.startswith('function ') or group.startswith('type ')) and values['symbol']:
					before = values['symbol']; values['symbol'] = before.replace(old_identity, identity)
					renames += ['--redefine-sym', before + '=' + values['symbol']]
			e.run(['objcopy', *renames, sdk / 'middle.o', control / 'middle.o'])
			groups['object']['sha256'] = hashlib.sha256((control / 'middle.o').read_bytes()).hexdigest()
			(control / 'middle.asti').write_text(metadata['reseal'](groups))
			strict_command = [str(arg).replace(str(sdk) + '/', str(control) + '/') for arg in command]
			e.run(strict_command, cwd=control)
			e.run([control / 'consumer'], stdout=expected, cwd=control)
			e.files(*[p for p in control.iterdir() if p.is_file()])
			groups['dependency RecordLeaf']['compatibility'] = 'runtime/unknown'
			(control / 'middle.asti').write_text(metadata['reseal'](groups))
			e.run(strict_command, expected=1, contains='unknown dependency compatibility contract', cwd=control)
			e.files(control / 'middle.asti')
		e.files(*[p for p in sdk.iterdir() if p.is_file()])
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
