#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Frozen B4 opaque model/processing and setup, all O0/O2 mixes plus O1."""
from pathlib import Path
import hashlib
import itertools
import json
import resource
import shutil
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from freeze_guard import braid_guard, current_include_flags


def main(compiler, prefix, output, profile='regression'):
	assert profile in ('frozen', 'regression')
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	e = Evidence(compiler, output, 'runtime-composition-17-braid-sdk')
	guard = braid_guard(e.compiler, profile, prefix)
	e.data['qualification_guard'] = guard.record()
	guard.bind(e)
	e.data['profile'] = profile; e.data['regression_only'] = profile == 'regression'; e.save()
	build_mode = ['--regression'] if profile == 'regression' else []
	prefix = Path(prefix).resolve(); here = Path(__file__).resolve().parent; app = Path(__file__).resolve().parent
	def frozen():
		guard.check()
	frozen()
	leaf, middle = app / 'braid-model.astra', app / 'braid-setup.astra'
	contexts = ROOT / 'lib/bindings/memory/contexts.vapi'
	vapis = [contexts, ROOT / 'lib/bindings/async/composition.vapi', ROOT / 'lib/bindings/async/payload.vapi', app / 'braid-host.vapi']
	providers = [app / 'braid-host.c', app / 'braid-provider.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/async/linux.c', ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/runtime/monitors-13.c', ROOT / 'lib/runtime/platform/network-posix.c', ROOT / 'lib/runtime/platform/text-posix.c', ROOT / 'lib/runtime/platform/args-posix.c']
	consumer_sources = [app / ('braid-' + name + '.astra') for name in ['common', 'workers', 'service']] + [ROOT / 'lib/astra/hosted/network.astra', ROOT / 'lib/astra/async/payload.astra']
	e.files(leaf, middle, *consumer_sources, *providers, *vapis, Path(__file__), here / 'braid-peer.py', app / 'braid-provider.h', prefix / 'lib/liburing.a')
	for name in ['task-core17.c', 'task-api17.c', 'worker17.c', 'virtual.h', 'provider.h', 'linux.h']: e.files(ROOT / 'lib/runtime/async' / name)
	for name in ['context-17.h', 'monitors-13.h']: e.files(ROOT / 'lib/runtime/runtime' / name)
	objects = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', *current_include_flags(e.output), '-isystem', prefix / 'include', '-c', provider, '-o', obj]); objects.append(obj); e.files(obj)
	selectors = ['Fault', 'Interval', 'Triple', 'Costs', 'Scores', 'Moments', 'Alignment', 'Layer<BraidModel.Alignment>', 'Box<BraidModel.Alignment>', 'Reply<BraidModel.Alignment>', 'Envelope<BraidModel.Alignment>', 'Entry', 'Block', 'Ticket', 'Queue', 'Cache', 'empty_entry', 'clone_ticket', 'clone_queue', 'clone_cache', 'clone_entry', 'lookup', 'reply']
	exports = [arg for name in selectors for arg in ['--native-export', 'BraidModel.' + name]]
	e.data['variants'] = []; e.data['freeze'] = 4; e.data['challenge_complete'] = False; e.save()
	for levels in [*itertools.product('02', repeat=3), ('1', '1', '1')]:
		frozen(); stem = 'units-' + ''.join(levels); case = e.output / stem; attempt = 1
		while case.exists():
			case = e.output / (stem + '-attempt-' + str(attempt)); attempt += 1
		case.mkdir()
		producer = case / 'producer-sources'; producer.mkdir(exist_ok=True)
		shutil.copyfile(leaf, producer / leaf.name); shutil.copyfile(middle, producer / middle.name)
		e.run([e.compiler, '-O' + levels[0], '-c', producer / leaf.name, '--vapi', contexts, '--vapi', app / 'braid-host.vapi', '--module', 'BraidModel', *exports, '--emit-interface', case / 'data.asti', '-o', case / 'data.o'])
		e.run([e.compiler, '-O' + levels[1], '-c', producer / middle.name, '--vapi', contexts, '--module', 'BraidSetup', '--native-export', 'BraidSetup.queue', '--native-export', 'BraidSetup.cache', '--native-export', 'BraidSetup.ticket', '--import-module', case / 'data.asti', '--emit-interface', case / 'setup.asti', '-o', case / 'setup.o'])
		hidden = case / 'hidden-producer-sources'; producer.rename(hidden)
		sdk = case / 'sdk'; sdk.mkdir(exist_ok=True)
		for path in [*[case / name for name in ['data.asti', 'data.o', 'setup.asti', 'setup.o']], *vapis, *objects]: shutil.copyfile(path, sdk / path.name)
		shutil.copyfile(e.compiler, sdk / 'astrac'); (sdk / 'astrac').chmod(0o755)
		for path in consumer_sources: shutil.copyfile(path, sdk / path.name)
		assert not producer.exists() and not (sdk / leaf.name).exists() and not (sdk / middle.name).exists()
		command = [sdk / 'astrac', '-O' + levels[2], '--entry-object', *[sdk / p.name for p in consumer_sources], *[arg for path in vapis for arg in ['--vapi', sdk / path.name]], '--import-module', sdk / 'setup.asti', '-o', sdk / 'consumer.o']
		trace = sdk / 'compiler-opens.log'
		e.run(['strace', '-f', '-e', 'trace=openat,openat2', '-o', trace, *command], cwd=sdk)
		opened = trace.read_text()
		assert all(str(path) not in opened for path in [leaf, middle, producer / leaf.name, producer / middle.name, hidden / leaf.name, hidden / middle.name])
		e.run(['cc', '-pthread', sdk / 'consumer.o', sdk / 'data.o', sdk / 'setup.o', *[sdk / p.name for p in objects], prefix / 'lib/liburing.a', '-o', sdk / 'braid-service'], cwd=sdk)
		for family in (['4', '6'] if levels in [('2', '2', '2'), ('1', '1', '1')] else ['4']):
			receipt, data = case / ('peer-' + family + '.json'), case / ('input-' + family + '.bin')
			e.run(['python3', here / 'braid-peer.py', '--product', sdk / 'braid-service', '--output', data, '--receipt', receipt, '--family', family], stdout='PASS: weighted range edit, independent shortest paths, cache reuse and TCP/UDP progress\n', timeout=120)
			assert json.loads(receipt.read_text())['status'] == 'PASS'; e.files(receipt, data)
		e.data['variants'].append(dict(levels=list(levels), hidden_producer_paths=True, traced_no_source_reads=True)); e.save()
		e.files(*[p for p in sdk.iterdir() if p.is_file()], *[p for p in hidden.iterdir() if p.is_file()])
	frozen(); e.complete()


if __name__ == '__main__': main(*sys.argv[1:])
