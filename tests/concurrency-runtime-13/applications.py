# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute the distinct checked-in Surge 13 application sources and C oracles."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument

HERE = Path(__file__).parent
APPS = ROOT / 'examples/concurrency-runtime-13'
RUNTIME = ROOT / 'lib/runtime/runtime'
THREADS = RUNTIME / 'threads-13.c'
MONITORS = RUNTIME / 'monitors-13.c'
ERRORS = ROOT / 'lib/astra/base/errors.astra'
UTF8 = ROOT / 'lib/astra/text/utf8-message.astra'
THREADED = ROOT / 'lib/astra/async/threaded.astra'
POOL = ROOT / 'lib/runtime/async/threaded.c'
TEXT = ROOT / 'lib/runtime/platform/text-posix.c'
NETWORK = ROOT / 'lib/astra/hosted/network.astra'
SOCKETS = ROOT / 'lib/runtime/platform/network-posix.c'
SOCKET_FLAGS = ['-Wl,--wrap=' + name for name in ['socket', 'accept4', 'close', 'send', 'recv']]
THREAD_LINE = 'native threads: 4 simultaneous identities, 4 exact environment destructions\n'
CASES = {
	'A109': ('a109-image-tiles.astra', [], [THREADS, MONITORS, HERE / 'weak-race-oracle.c', HERE / 'application-oracle.c'], [], None,
	'weak race: four native workers, one payload destruction, expired upgrade\napplication A109: independent values and exact owned lifetimes\n'),
	'A110': ('a110-resource-registry.astra', [], [MONITORS, HERE / 'application-oracle.c'], [], None,
	'application A110: independent values and exact owned lifetimes\n'),
	'A111': ('a111-boxed-snapshots.astra', [], [THREADS, MONITORS, HERE / 'thread-oracle.c', HERE / 'application-oracle.c'], [], None,
	THREAD_LINE + 'application A111: independent values and exact owned lifetimes\n'),
	'A112': ('a112-monitored-ledger.astra', [ERRORS], [THREADS, MONITORS, HERE / 'thread-oracle.c'], [], None, THREAD_LINE),
	'A113': ('a113-guarded-transfer.astra', [], [THREADS, MONITORS, HERE / 'thread-oracle.c', HERE / 'application-oracle.c'], [], None,
	THREAD_LINE + 'application A113: independent values and exact owned lifetimes\n'),
	'A114': ('a114-singleton-configuration.astra', [ERRORS], [THREADS, MONITORS, RUNTIME / 'singletons-13.c', HERE / 'singleton-oracle.c', HERE / 'thread-oracle.c'], [], None,
	'singleton: failed initialization retried, one racing publication, quiescent shutdown\n' + THREAD_LINE),
	'A115': ('a115-callback-broker.astra', [ERRORS], [THREADS, MONITORS, HERE / 'callback-affinity-oracle.c'],
	['-Wl,--wrap=astra_thread_register', '-Wl,--wrap=astra_thread_retire'], 'run_callback_affinity',
	'C callback boundary: four retained contexts, foreign worker entry, caught native error, joined retirement; local ThreadBound callback preserved\n'),
	'A116': ('a116-parallel-batch.astra', [THREADED, ERRORS], [POOL, TEXT, HERE / 'task-stress-oracle.c'], [], None,
	'task stress: 4 simultaneous workers, 4 migrated batches, checked errors, cold/active/shutdown cleanup\n'),
	'A117': ('a117-framed-service.astra', [NETWORK, THREADED, ERRORS, UTF8], [POOL, TEXT, SOCKETS, HERE / 'network-oracle.c', HERE / 'network-listener-oracle.c'], SOCKET_FLAGS, 'run_listener',
	'Astra TCP listener: 4 concurrent peers, exact binary frames, refused connect, busy bind, bounded buffers, all sockets closed\n'),
	'A118': ('a118-udp-telemetry.astra', [NETWORK, THREADED, ERRORS], [POOL, TEXT, SOCKETS, HERE / 'network-oracle.c', HERE / 'udp-oracle.c'], SOCKET_FLAGS, 'run_udp',
	'UDP: two producers, exact endpoints, empty/max/delayed datagrams, checked truncation and limits, three exact closes\n'),
	'A119': ('a119-actor-worker.astra', [ERRORS], [THREADS, RUNTIME / 'actors-13.c', HERE / 'actor-stress-oracle.c'], [], None,
	'native Actor: 4 concurrent producers, 512 FIFO messages, all attempted owners retired\n'),
	'A120': ('a120-diagnostics-service.astra', [NETWORK, THREADED, ERRORS, UTF8],
	[THREADS, MONITORS, RUNTIME / 'singletons-13.c', POOL, TEXT, SOCKETS, HERE / 'callback-affinity-oracle.c', HERE / 'network-oracle.c', HERE / 'network-listener-oracle.c', HERE / 'udp-oracle.c', HERE / 'application-oracle.c', HERE / 'application-network-oracle.c'],
	[*SOCKET_FLAGS, '-Wl,--wrap=astra_thread_register', '-Wl,--wrap=astra_thread_retire', '-Wl,--wrap=net_oracle_lifetimes'], 'run_diagnostics',
	'C callback boundary: four retained contexts, foreign worker entry, caught native error, joined retirement; local ThreadBound callback preserved\n'
	+ 'Astra TCP listener: 4 concurrent peers, exact binary frames, refused connect, busy bind, bounded buffers, all sockets closed\n'
	+ 'UDP: two producers, exact endpoints, empty/max/delayed datagrams, checked truncation and limits, three exact closes\n'
	+ 'application A120: independent values and exact owned lifetimes\n'),
}


def main(compiler, output, *selected):
	e = Evidence(compiler, output, 'concurrency-applications')
	if not selected:
		assert set(CASES) == {f'A{n}' for n in range(109, 121)}, 'the complete A109-A120 source inventory is required'
		selected = sorted(CASES)
	assert set(selected) <= set(CASES) and len(set(selected)) == len(selected)
	e.data['selected_applications'] = list(selected)
	e.data['applications'] = {}
	objects = {}
	for app in selected:
		name, libraries, providers, flags, external, expected = CASES[app]
		source = APPS / name
		astra = [source, *libraries]
		case = e.output / app; case.mkdir(exist_ok=True)
		for provider in providers:
			if provider not in objects:
				obj = e.output / (provider.stem + '.o')
				e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
				objects[provider] = obj
		links = [item for provider in providers for item in ['--link-object', objects[provider]]]
		entry = None
		if external:
			entry = case / 'entry.c'; entry.write_text(f'extern int {external}(void);int main(void){{return {external}();}}\n')
		for level in ['O0', 'O1', 'O2']:
			product = case / level
			if external:
				obj = case / (level + '.o')
				e.run([e.compiler, '-' + level, '-c', *astra, '-o', obj])
				e.run(['cc', '-pthread', obj, *[objects[p] for p in providers], entry, *flags, '-o', product])
			else:
				e.run([e.compiler, '-' + level, *astra, *links, '--link-library', 'pthread', '-o', product])
			e.run([product], stdout=expected, timeout=45)
			e.files(product)
		e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', case / 'O2'], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
		if app in ['A109', 'A110', 'A111', 'A113', 'A120']:
			for sanitizer in ['address', 'thread']:
				instrument(e, app, astra, providers, expected, sanitizer, flags)
		e.files(*astra, *providers)
		if entry: e.files(entry)
		e.data['applications'][app] = dict(source=str(source.relative_to(ROOT)), levels=['O0', 'O1', 'O2'], expected_stdout=expected, status='PASS')
		e.save()
	e.files(Path(__file__), HERE / 'sanitizers.py')
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
