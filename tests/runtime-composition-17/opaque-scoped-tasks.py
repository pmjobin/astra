#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real opaque native factories and tasks retain their caller's scoped debt."""
from pathlib import Path
import re
import runpy
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def instrument_units(e, producer, sdk, exports, providers, flags, vapi, expected):
	target = dict(line.split('=', 1) for line in e.run([e.compiler, '--target-info']).stdout.splitlines() if '=' in line)
	objects = []
	for role in ['producer', 'consumer']:
		if role == 'producer':
			cmd = [e.compiler, '-O1', '-c', '--dump-llvm', producer, '--vapi', vapi, '--module', 'OpaqueScope', *exports, '--emit-interface', e.output / 'address-producer.asti', '-o', e.output / 'address-producer.o']
		else:
			cmd = [sdk / 'astrac', '-O1', '--dump-llvm', sdk / 'consumer.astra', '--vapi', sdk / vapi.name, '--import-module', sdk / 'producer.asti']
		code = e.run(cmd, cwd=sdk).stdout
		if role == 'producer':
			assert not (e.output / 'address-producer.asti').exists() and not (e.output / 'address-producer.o').exists()
		code = f'target datalayout = "{target["data-layout"]}"\ntarget triple = "{target["target"]}"\n' + code
		code = re.sub(r'^(define .*?)\s*\{\s*$', r'\1 sanitize_address {', code, flags=re.M)
		raw = e.output / (role + '-address.ll')
		modified = raw.with_name(role + '-address-instrumented.ll')
		obj = raw.with_suffix('.o')
		raw.write_text(code)
		e.run(['opt', '-passes=default<O1>,asan', '-S', raw, '-o', modified])
		assert '__asan_report' in modified.read_text()
		e.run(['llc', '-O1', '-filetype=obj', '-relocation-model=pic', modified, '-o', obj])
		objects.append(obj)
		e.files(raw, modified, obj)
	product = e.output / 'native-address'
	e.run(['clang', '-std=c11', '-O1', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-fsanitize=address,undefined', *objects, *providers, *flags, '-o', product])
	e.run([product], stdout=expected, env={'ASAN_OPTIONS': 'detect_leaks=1:halt_on_error=1', 'UBSAN_OPTIONS': 'halt_on_error=1'})
	e.files(product)


def main(compiler, output, profile='scalar'):
	assert profile in ['scalar', 'constructor', 'record']
	e = Evidence(compiler, output, 'runtime-composition-17-opaque-scoped-tasks-' + profile)
	here = Path(__file__).resolve().parent
	producer = here / 'opaque-scoped-task-producer.astra'
	original = here / 'opaque-scoped-task-consumer.astra'
	consumer = e.output / 'consumer.astra'
	text = original.read_text()
	if profile == 'constructor':
		text = text.replace('OpaqueScope.make(context, mode + 1)', 'new(context) OpaqueScope.Leaf(mode + 1)')
	elif profile == 'record':
		start = text.index('\tint value = await OpaqueScope.read(')
		end = text.index('\n}', start)
		text = text[:start] + '\tOpaqueScope.Packet input_packet = { child = move input, marker = mode + 31 };\n\tOpaqueScope.Packet output_packet = await OpaqueScope.relay(move input_packet, mode);\n\tif (!native_scope_inspect(output_packet, mode)) { throw new OpaqueScope.Fault("record"); }' + text[end:]
		text += '\nbool native_scope_inspect(borrowed OpaqueScope.Packet packet, int mode) { return packet.marker == mode + 31 && packet.child.read() == mode + 1; }\n'
	consumer.write_text(text)
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	providers = [here / 'opaque-scoped-task-oracle.c', ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/async/virtual.c', ROOT / 'lib/runtime/platform/text-posix.c']
	flags = ['-Wl,--wrap=astra_async_run', '-Wl,--wrap=astra_async_delay']
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links.append(obj)
		e.files(obj)
	exports = [arg for name in ['Leaf', 'Fault', 'Packet', 'make', 'read', 'relay'] for arg in ['--native-export', 'OpaqueScope.' + name]]
	expected = 'opaque scoped task: success, cold drop, checked error and joined cancellation retire every input once\n'
	metadata = runpy.run_path(str(ROOT / 'tests/structural-generics-15/units.py'))
	for levels in ['00', '02', '20', '22', '11']:
		case = e.output / ('units-' + levels)
		case.mkdir(exist_ok=True)
		e.run([e.compiler, '-O' + levels[0], '-c', producer, '--vapi', vapi, '--module', 'OpaqueScope', *exports, '--emit-interface', case / 'producer.asti', '-o', case / 'producer.o'])
		sdk = case / 'sdk'
		sdk.mkdir(exist_ok=True)
		for path in [case / 'producer.asti', case / 'producer.o', consumer, vapi, e.compiler]:
			shutil.copyfile(path, sdk / path.name)
		(sdk / 'astrac').chmod(0o755)
		assert sorted(p.name for p in sdk.glob('*.astra')) == ['consumer.astra']
		cmd = [sdk / 'astrac', '-O' + levels[1], '-c', sdk / 'consumer.astra', '--vapi', sdk / vapi.name, '--import-module', sdk / 'producer.asti', '-o', sdk / 'consumer.o']
		e.run(cmd, cwd=sdk)
		e.run(['cc', '-pthread', *flags, sdk / 'consumer.o', sdk / 'producer.o', *links, '-o', sdk / 'consumer'])
		e.run([sdk / 'consumer'], stdout=expected, cwd=sdk)
		if levels == '22':
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', sdk / 'consumer'], stdout=expected, contains='ERROR SUMMARY: 0 errors', cwd=sdk)
			trace = sdk / 'opens.log'
			e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *cmd], cwd=sdk)
			opened = trace.read_text()
			assert str(producer) not in opened and str(sdk / 'producer.asti') in opened
			for name in ['version', 'removed', 'weakened']:
				bad = sdk / ('mutant-' + name)
				bad.mkdir(exist_ok=True)
				shutil.copyfile(sdk / 'producer.o', bad / 'producer.o')
				groups = metadata['metadata']((sdk / 'producer.asti').read_text())
				function = groups['function F:OpaqueScope.read']
				if name == 'version': function['lifetimes'] = function['lifetimes'].replace('summary/1', 'summary/9')
				elif name == 'removed': del function['lifetimes']
				else: function['lifetimes'] = 'runtime-lifetime-summary/1:incomplete'
				(bad / 'producer.asti').write_text(metadata['reseal'](groups))
				e.run([sdk / 'astrac', '-c', sdk / 'consumer.astra', '--vapi', sdk / vapi.name, '--import-module', bad / 'producer.asti', '-o', bad / 'refused.o'], expected=1, contains='invalid versioned lifetime contract' if name == 'version' else 'missing/unknown interface field' if name == 'removed' else 'fingerprint mismatch', cwd=sdk)
				e.files(bad / 'producer.asti', bad / 'producer.o')
			e.files(trace)
		for p in sdk.iterdir():
			if p.is_file(): e.files(p)
	instrument_units(e, producer, sdk, exports, providers, flags, vapi, expected)
	for name, changed, diagnostic in [
		('retired-backing', text.replace('native_scope_begin(mode);', 'release backing; native_scope_begin(mode);'), 'exclusively borrowed'),
		('moved-input', text.replace('var pending = native_scope_parent(move input, mode);', 'var pending = native_scope_parent(move input, mode); int stale = input.read();'), 'moved'),
	]:
		assert changed != text
		negative = e.output / (name + '.astra')
		negative.write_text(changed)
		e.run([e.compiler, '--check', negative, '--vapi', vapi, '--import-module', e.output / 'units-11/producer.asti'], expected=1, contains=diagnostic)
		e.files(negative)
	e.files(producer, original, consumer, vapi, Path(__file__), *providers, ROOT / 'tests/structural-generics-15/units.py', ROOT / 'tests/systems-dsp-9/support.py', ROOT / 'lib/runtime/runtime/context-17.h')
	for name in ['virtual.h', 'provider.h', 'task-core17.c', 'task-api17.c']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
