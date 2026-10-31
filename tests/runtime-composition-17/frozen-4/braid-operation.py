#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Frozen B4 configurations, actual provider failures and joined cancellation."""
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
	e = Evidence(compiler, output, 'runtime-composition-17-braid-operation')
	guard = braid_guard(e.compiler, profile, prefix)
	e.data['qualification_guard'] = guard.record()
	guard.bind(e)
	e.data['profile'] = profile; e.data['regression_only'] = profile == 'regression'; e.save()
	build_mode = ['--regression'] if profile == 'regression' else []
	prefix = Path(prefix).resolve(); here = Path(__file__).resolve().parent; app = Path(__file__).resolve().parent
	names = ['braid_prepare', 'braid_event', 'braid_finish', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked', 'astra_context17_destroy', 'astra_async_new_allocated', 'astra_async_linux_payload', 'astra_async_worker_pool_close']
	wrappers = ['-Wl,--wrap=' + name for name in names]
	build_flags = ['--c-source', here / 'braid-observer.c', '--c-flag=-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', *['--link-flag=' + flag for flag in wrappers]]
	expected = 'PASS: weighted range edit, independent shortest paths, cache reuse and TCP/UDP progress\n'
	e.data['freeze'] = 4; e.data['challenge_complete'] = False; e.data['configurations'] = []; e.save()
	for index, (queue, cache, workers, quota) in enumerate([(2, 3, 2, 98317), (6, 9, 5, 393241)]):
		level = str(index * 2); case = e.output / ('configured-' + level)
		e.run(['python3', app / 'build-braid.py', *build_mode, '--compiler', e.compiler, '--uring-prefix', prefix, '--output', case, '--optimization', level, *build_flags])
		environment = {'ASTRA_BRAID_QUEUE': str(queue), 'ASTRA_BRAID_CACHE': str(cache), 'ASTRA_BRAID_WORKERS': str(workers), 'ASTRA_BRAID_QUOTA': str(quota)}
		for family in ['4', '6']:
			receipt, data = case / ('peer-' + family + '.json'), case / ('input-' + family + '.bin')
			e.run(['python3', here / 'braid-peer.py', '--product', case / ('braid-service-O' + level), '--output', data, '--receipt', receipt, '--family', family], stdout=expected, timeout=120, env=environment)
			result = json.loads(receipt.read_text()); assert result['status'] == 'PASS'
			observed = [json.loads(line) for line in result['stdout'].splitlines() if 'observed_profile' in line]; assert len(observed) == 1
			e.data['configurations'].append(dict(queue=queue, cache=cache, workers=workers, quota=quota, level=level, family=family, observed=observed[0])); e.save(); e.files(receipt, data)
		for mode in ['cpu', 'io', 'bad-fd', 'eof']:
			receipt, data = case / (mode + '.json'), case / (mode + '.bin')
			e.run(['python3', here / 'braid-failure-peer.py', '--product', case / ('braid-service-O' + level), '--output', data, '--receipt', receipt, '--family', '6', '--mode', mode], stdout='PASS: braid ' + mode + ', observed outcome and exact joined conservation\n', timeout=120, env=environment); e.files(receipt, data)
		e.files(case / ('braid-service-O' + level), case / ('braid-service-O' + level + '.o'), case / ('build-O' + level + '.json'))
	sources = [app / ('braid-' + name + '.astra') for name in ['model', 'common', 'setup', 'workers', 'service']] + [ROOT / 'lib/astra/hosted/network.astra', ROOT / 'lib/astra/async/payload.astra']
	vapis = [ROOT / 'lib/bindings/memory/contexts.vapi', ROOT / 'lib/bindings/async/composition.vapi', ROOT / 'lib/bindings/async/payload.vapi', app / 'braid-host.vapi']
	providers = [app / 'braid-host.c', app / 'braid-provider.c', ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/async/linux.c', ROOT / 'lib/runtime/runtime/context-17.c', ROOT / 'lib/runtime/runtime/monitors-13.c', ROOT / 'lib/runtime/platform/network-posix.c', ROOT / 'lib/runtime/platform/text-posix.c', ROOT / 'lib/runtime/platform/args-posix.c', here / 'braid-observer.c']
	for sanitizer in ['address', 'thread']:
		def execute(product, environment):
			receipt, data = e.output / (sanitizer + '.json'), e.output / (sanitizer + '.bin')
			e.run(['python3', here / 'braid-peer.py', '--product', product, '--output', data, '--receipt', receipt, '--family', '4'], stdout=expected, timeout=120, env=environment); e.files(receipt, data)
			for mode in ['cpu', 'io', 'bad-fd', 'eof']:
				receipt, data = e.output / (sanitizer + '-' + mode + '.json'), e.output / (sanitizer + '-' + mode + '.bin')
				e.run(['python3', here / 'braid-failure-peer.py', '--product', product, '--output', data, '--receipt', receipt, '--family', '6', '--mode', mode], stdout='PASS: braid ' + mode + ', observed outcome and exact joined conservation\n', timeout=120, env=environment); e.files(receipt, data)
		instrument(e, 'braid-observed', sources, providers, '', sanitizer, link_flags=[*current_include_flags(e.output), '-DASTRA_ASYNC_LINUX_TEST_PROTOCOL', '-isystem', prefix / 'include', prefix / 'lib/liburing.a', *wrappers], vapis=vapis, execute=execute)
	e.files(Path(__file__), here / 'braid-peer.py', here / 'braid-failure-peer.py', app / 'build-braid.py', app / 'braid-provider.h', prefix / 'lib/liburing.a', ROOT / 'tests/concurrency-runtime-13/sanitizers.py')
	for name in ['task-core17.c', 'task-api17.c', 'worker17.c', 'virtual.h', 'provider.h', 'linux.h']: e.files(ROOT / 'lib/runtime/async' / name)
	guard.check(); e.complete()


if __name__ == '__main__': main(*sys.argv[1:])
