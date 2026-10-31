#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify the frozen weighted range-alignment service with independent peers and tools."""
from pathlib import Path
import json
import resource
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from freeze_guard import braid_guard, current_include_flags
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, prefix, output, profile='regression'):
	assert profile in ('frozen', 'regression')
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	e = Evidence(compiler, output, 'runtime-composition-17-braid-application')
	guard = braid_guard(e.compiler, profile, prefix)
	e.data['qualification_guard'] = guard.record()
	guard.bind(e)
	e.data['profile'] = profile; e.data['regression_only'] = profile == 'regression'; e.save()
	build_mode = ['--regression'] if profile == 'regression' else []
	prefix = Path(prefix).resolve(); here = Path(__file__).resolve().parent; app = Path(__file__).resolve().parent
	expected = 'PASS: weighted range edit, independent shortest paths, cache reuse and TCP/UDP progress\n'
	e.data['freeze'] = 4; e.data['challenge_complete'] = False; e.save()
	for level in ['0', '1', '2']:
		case = e.output / ('O' + level)
		e.run(['python3', app / 'build-braid.py', *build_mode, '--compiler', e.compiler, '--uring-prefix', prefix, '--output', case, '--optimization', level])
		for family in ['4', '6']:
			receipt, data = case / ('peer-' + family + '.json'), case / ('input-' + family + '.bin')
			e.run(['python3', here / 'braid-peer.py', '--product', case / ('braid-service-O' + level), '--output', data, '--receipt', receipt, '--family', family], stdout=expected, timeout=120)
			assert json.loads(receipt.read_text())['status'] == 'PASS'; e.files(receipt, data)
		e.files(case / ('braid-service-O' + level), case / ('braid-service-O' + level + '.o'), case / ('build-O' + level + '.json'))
	case = e.output / 'O2'; receipt, data = case / 'valgrind.json', case / 'valgrind.bin'
	e.run(['python3', here / 'braid-peer.py', '--product', case / 'braid-service-O2', '--output', data, '--receipt', receipt, '--family', '6', '--valgrind', '--allow-serialized-tools'], stdout=expected, timeout=180)
	e.files(receipt, data)
	sources = [app / ('braid-' + name + '.astra') for name in ['model', 'common', 'setup', 'workers', 'service']] + [ROOT / 'lib/astra/hosted/network.astra', ROOT / 'lib/astra/async/payload.astra']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', ROOT / 'lib/bindings/async/composition.vapi', ROOT / 'lib/bindings/async/payload.vapi', app / 'braid-host.vapi']
	providers = [app / 'braid-host.c', app / 'braid-provider.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/async/linux.c', ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/runtime/monitors-13.c', ROOT / 'lib/runtime/platform/network-posix.c', ROOT / 'lib/runtime/platform/text-posix.c', ROOT / 'lib/runtime/platform/args-posix.c']
	for sanitizer in ['address', 'thread']:
		def execute(product, environment):
			receipt, data = e.output / (sanitizer + '.json'), e.output / (sanitizer + '.bin')
			e.run(['python3', here / 'braid-peer.py', '--product', product, '--output', data, '--receipt', receipt, '--family', '4'], stdout=expected, timeout=180, env=environment)
			e.files(receipt, data)
		instrument(e, 'braid', sources, providers, '', sanitizer, link_flags=[*current_include_flags(e.output), '-isystem', prefix / 'include', prefix / 'lib/liburing.a'], vapis=vapis, execute=execute)
	e.files(Path(__file__), here / 'braid-peer.py', app / 'build-braid.py', app / 'braid-provider.h', prefix / 'lib/liburing.a', ROOT / 'tests/concurrency-runtime-13/sanitizers.py')
	for name in ['task-core17.c', 'task-api17.c', 'worker17.c', 'virtual.h', 'provider.h', 'linux.h']: e.files(ROOT / 'lib/runtime/async' / name)
	guard.check(); e.complete()


if __name__ == '__main__': main(*sys.argv[1:])
