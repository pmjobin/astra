#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Opaque native methods replace original scoped fields without losing debt."""
from pathlib import Path
import re
import runpy
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-mutable-scoped-field-units')
	here = Path(__file__).resolve().parent
	original = here / 'mutable-scoped-fields.astra'
	text = original.read_text()
	cut = text.index('int mutable_case(')
	producer = e.output / 'producer.astra'
	consumer = e.output / 'consumer.astra'
	producer.write_text('namespace OpaqueScope;\n' + text[:cut])
	caller = 'extern(C) int mutable_check(int phase);\n' + text[cut:]
	for name in ['MutableLeaf', 'MutableEnvelope']:
		caller = re.sub(r'\b' + name + r'\b', 'OpaqueScope.' + name, caller)
	consumer.write_text(caller)
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [ROOT / 'lib/runtime/runtime/context-17.c', here / 'mutable-scoped-fields-oracle.c']
	links = []
	for path in providers:
		obj = e.output / (path.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', path, '-o', obj])
		links.append(obj)
		e.files(obj)
	exports = [item for name in ['MutableLeaf', 'MutableEnvelope'] for item in ['--native-export', 'OpaqueScope.' + name]]
	expected = 'scoped mutation: old generations retire once and replacements retain their exact contexts\n'
	metadata = runpy.run_path(str(ROOT / 'tests/structural-generics-15/units.py'))
	for levels in ['00', '02', '20', '22', '11']:
		case = e.output / ('units-' + levels)
		case.mkdir(exist_ok=True)
		e.run([e.compiler, '-O' + levels[0], '-c', producer, '--vapi', vapi, '--module', 'OpaqueScope', *exports, '--emit-interface', case / 'producer.asti', '-o', case / 'producer.o'])
		sdk = case / 'sdk'
		sdk.mkdir(exist_ok=True)
		for path in [case / 'producer.asti', case / 'producer.o', consumer, vapi, e.compiler]: shutil.copyfile(path, sdk / path.name)
		(sdk / 'astrac').chmod(0o755)
		assert sorted(p.name for p in sdk.glob('*.astra')) == ['consumer.astra']
		cmd = [sdk / 'astrac', '-O' + levels[1], '-c', sdk / 'consumer.astra', '--vapi', sdk / vapi.name, '--import-module', sdk / 'producer.asti', '-o', sdk / 'consumer.o']
		e.run(cmd, cwd=sdk)
		e.run(['cc', '-pthread', sdk / 'consumer.o', sdk / 'producer.o', *links, '-o', sdk / 'consumer'])
		e.run([sdk / 'consumer'], stdout=expected, cwd=sdk)
		if levels == '22':
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout=expected, contains='ERROR SUMMARY: 0 errors', cwd=sdk)
			trace = sdk / 'opens.log'
			e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *cmd], cwd=sdk)
			assert str(producer) not in trace.read_text() and str(sdk / 'producer.asti') in trace.read_text()
			for name in ['version', 'removed', 'weakened']:
				bad = sdk / ('mutant-' + name)
				bad.mkdir(exist_ok=True)
				shutil.copyfile(sdk / 'producer.o', bad / 'producer.o')
				groups = metadata['metadata']((sdk / 'producer.asti').read_text())
				function = groups['function C:OpaqueScope.MutableEnvelope::replace']
				if name == 'version': function['lifetimes'] = function['lifetimes'].replace('summary/1', 'summary/9')
				elif name == 'removed': del function['lifetimes']
				else: function['lifetimes'] = 'runtime-lifetime-summary/1:incomplete'
				(bad / 'producer.asti').write_text(metadata['reseal'](groups))
				e.run([sdk / 'astrac', '-c', sdk / 'consumer.astra', '--vapi', sdk / vapi.name, '--import-module', bad / 'producer.asti', '-o', bad / 'refused.o'], expected=1, contains='invalid versioned lifetime contract' if name == 'version' else 'missing/unknown interface field' if name == 'removed' else 'fingerprint mismatch', cwd=sdk)
				e.files(bad / 'producer.asti', bad / 'producer.o')
			e.files(trace)
		for path in sdk.iterdir():
			if path.is_file(): e.files(path)
	instrument = runpy.run_path(str(here / 'opaque-scoped-tasks.py'))['instrument_units']
	instrument(e, producer, sdk, exports, providers, [], vapi, expected)
	for name, changed, diagnostic in [
		('moved-input', caller.replace('if (envelope.read() != 2', 'int stale = replacement.read(); if (envelope.read() != 2'), 'moved'),
		('retired-backing', caller.replace('var last = new(first)', 'release first_backing; var last = new(first)'), 'exclusively borrowed'),
	]:
		assert changed != caller
		negative = e.output / (name + '.astra')
		negative.write_text(changed)
		e.run([e.compiler, '--check', negative, '--vapi', vapi, '--import-module', e.output / 'units-11/producer.asti'], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(original, producer, consumer, Path(__file__), vapi, *providers, ROOT / 'lib/runtime/runtime/context-17.h', here / 'opaque-scoped-tasks.py', ROOT / 'tests/structural-generics-15/units.py', ROOT / 'tests/systems-dsp-9/support.py')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
