#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run streaming A using opaque runtime data and composition libraries."""
from pathlib import Path
import configparser
import hashlib
import itertools
import json
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, prefix, output):
	e = Evidence(compiler, output, 'runtime-composition-17-stream-sdk')
	prefix = Path(prefix).resolve(); here = Path(__file__).resolve().parent
	app = ROOT / 'examples/runtime-composition-17'
	leaf, middle = app / 'stream-pipeline.astra', app / 'stream-factories.astra'
	contexts = ROOT / 'lib/bindings/memory/contexts.vapi'
	vapis = [contexts, ROOT / 'lib/bindings/async/composition.vapi', ROOT / 'lib/bindings/async/payload.vapi', app / 'stream-host.vapi']
	providers = [app / 'stream-host.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/async/linux.c', ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/runtime/monitors-13.c', ROOT / 'lib/runtime/platform/network-posix.c', ROOT / 'lib/runtime/platform/text-posix.c', ROOT / 'lib/runtime/platform/args-posix.c', here / 'stream-protocol-oracle.c']
	consumer_sources = [app / ('stream-' + name + '.astra') for name in ['common', 'worker', 'stages', 'spool']] + [ROOT / 'lib/astra/base/errors.astra', ROOT / 'lib/astra/hosted/network.astra', ROOT / 'lib/astra/async/payload.astra']
	wrappers = ['-Wl,--wrap=' + name for name in ['stream_prepare', 'stream_event', 'stream_finish', 'stream_stop_requested', 'astra_net_read', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'astra_async_new_allocated', 'astra_async_worker_pool_close']]
	e.files(leaf, middle, *consumer_sources, *providers, *vapis, Path(__file__), here / 'stream-peer.py', prefix / 'lib/liburing.a')
	for name in ['task-core17.c', 'task-api17.c', 'worker17.c', 'virtual.h', 'provider.h', 'linux.h']: e.files(ROOT / 'lib/runtime/async' / name)
	for name in ['context-17.h', 'monitors-13.h']: e.files(ROOT / 'lib/runtime/runtime' / name)
	objects = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', '-isystem', prefix / 'include', '-c', provider, '-o', obj])
		objects.append(obj); e.files(obj)
	selectors = ['Stream.Chunk', 'Stream.Queue', 'Stream.Progress', 'Stream.clone_chunk', 'Stream.clone_queue', 'Stream.clone_progress']
	exports = [arg for name in selectors for arg in ['--native-export', name]]
	for levels in [*itertools.product('02', repeat=3), ('1', '1', '1')]:
		case = e.output / ('units-' + ''.join(levels)); case.mkdir(exist_ok=True)
		e.run([e.compiler, '-O' + levels[0], '-c', leaf, '--vapi', contexts, '--vapi', app / 'stream-host.vapi', '--module', 'Stream', *exports, '--emit-interface', case / 'data.asti', '-o', case / 'data.o'])
		e.run([e.compiler, '-O' + levels[1], '-c', middle, '--vapi', contexts, '--module', 'StreamSetup', '--native-export', 'StreamSetup.create_queue', '--native-export', 'StreamSetup.create_progress', '--import-module', case / 'data.asti', '--emit-interface', case / 'factories.asti', '-o', case / 'factories.o'])
		sdk = case / 'sdk'; sdk.mkdir(exist_ok=True)
		for path in [*[case / name for name in ['data.asti', 'data.o', 'factories.asti', 'factories.o']], *vapis, *objects]: shutil.copyfile(path, sdk / path.name)
		shutil.copyfile(e.compiler, sdk / 'astrac'); (sdk / 'astrac').chmod(0o755)
		for path in consumer_sources: shutil.copyfile(path, sdk / path.name)
		assert not (sdk / leaf.name).exists() and not (sdk / middle.name).exists()
		assert 'CONTEXT-BYTES' in (sdk / 'data.asti').read_text()
		command = [sdk / 'astrac', '-O' + levels[2], '--entry-object', *[sdk / p.name for p in consumer_sources], *[arg for path in vapis for arg in ['--vapi', sdk / path.name]], '--import-module', sdk / 'factories.asti', '-o', sdk / 'consumer.o']
		e.run(command, cwd=sdk)
		e.run(['cc', '-pthread', sdk / 'consumer.o', sdk / 'data.o', sdk / 'factories.o', *[sdk / p.name for p in objects], prefix / 'lib/liburing.a', *wrappers, '-o', sdk / 'stream-spool'], cwd=sdk)
		receipt, data = case / 'peer.json', case / 'output.bin'
		e.run(['python3', here / 'stream-peer.py', '--product', sdk / 'stream-spool', '--output', data, '--receipt', receipt, '--family', '4'], stdout='PASS: streaming peer, exact ordered transformed file and TCP/UDP progress\n', timeout=90)
		assert json.loads(receipt.read_text())['status'] == 'PASS'
		if levels == ('2', '2', '2'):
			trace = sdk / 'compiler-opens.log'
			e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
			assert str(leaf) not in trace.read_text() and str(middle) not in trace.read_text()
			# Replace only the provider implementation. The consumer and middle
			# object remain byte-identical; public declarations/effects/symbols agree.
			replacement = case / 'replacement'; replacement.mkdir(exist_ok=True)
			changed = leaf.read_text().replace('+ this.sequence % 31 + 17) % 256', '+ this.sequence % 31 + 29) % 256')
			assert changed != leaf.read_text()
			source = replacement / 'provider.astra'; source.write_text(changed)
			e.run([e.compiler, '-O2', '-c', source, '--vapi', contexts, '--vapi', app / 'stream-host.vapi', '--module', 'Stream', *exports, '--emit-interface', replacement / 'data.asti', '-o', replacement / 'data.o'])
			def public_abi(path):
				model = configparser.ConfigParser(interpolation=None); model.read(path)
				return {section: dict(model[section]) for section in model.sections() if section not in ['object', 'receipt']}
			assert public_abi(replacement / 'data.asti') == public_abi(sdk / 'data.asti')
			retained = {name: hashlib.sha256((sdk / name).read_bytes()).hexdigest() for name in ['consumer.o', 'factories.o']}
			e.run(['cc', '-pthread', sdk / 'consumer.o', replacement / 'data.o', sdk / 'factories.o', *[sdk / p.name for p in objects], prefix / 'lib/liburing.a', *wrappers, '-o', replacement / 'stream-spool'], cwd=sdk)
			new_receipt, new_data = replacement / 'peer.json', replacement / 'output.bin'
			e.run(['python3', here / 'stream-peer.py', '--product', replacement / 'stream-spool', '--output', new_data, '--receipt', new_receipt, '--family', '6', '--transform-bias', '29'], stdout='PASS: streaming peer, exact ordered transformed file and TCP/UDP progress\n', timeout=90)
			assert new_data.read_bytes() != data.read_bytes()
			assert retained == {name: hashlib.sha256((sdk / name).read_bytes()).hexdigest() for name in retained}
			e.data['provider_replacement'] = dict(retained_objects=retained, changed_bias=29, identical_public_abi=True)
			e.files(source, replacement / 'data.asti', replacement / 'data.o', replacement / 'stream-spool', new_receipt, new_data)
		e.files(receipt, data, *[p for p in sdk.iterdir() if p.is_file()])
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
