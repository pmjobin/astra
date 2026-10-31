#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Cooperative/worker observation without a Linux or context-provider dependency."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-virtual-bridge')
	common, worker, source = [e.output / name for name in ['common.astra', 'worker.astra', 'main.astra']]
	common.write_text('''class BridgeError : Error { init(string message) : base(message) {} }
enum Status { Completed, Cancelled }
async runtime VirtualExec throws BridgeError returns Status provider "virtual-composed";
''')
	worker.write_text('''namespace CPU;
enum WorkerStatus { Completed, Cancelled }
async runtime WorkerExec throws BridgeError returns WorkerStatus provider "posix-threaded-composed";
async int value(int seed, bool fail) throws Error {
	await delay_ticks(1);
	if (fail) { throw new Error("worker checked failure"); }
	return seed + 7;
}
''')
	source.write_text('''async void root(owned WorkerPool pool) throws Error {
	int value = await pool.submit(CPU.value(35, false));
	if (value != 42) { throw new Error("cooperative bridge result"); }
	bool caught = false;
	try { int unused = await pool.submit(CPU.value(0, true)); }
	catch (Error error) { if (error.message != "worker checked failure") { throw; } caught = true; }
	var cold = CPU.value(0, false);
	await pool.cancel_and_join(move cold);
	if (!caught) { throw new Error("missing bridge exception"); }
}
int main() {
	var pool = worker_pool(2);
	if (pool == null) { return 1; }
	try {
		var executor = VirtualExec.open(4);
		var status = executor.run(root(move pool));
		match (status) { case Status.Completed(): {} else: { return 2; } }
	} catch (Error error) { return 3; }
	return 0;
}
''')
	sources = [common, worker, source, ROOT / 'lib/astra/base/errors.astra']
	vapis = [ROOT / 'lib/bindings/async/composition.vapi']
	providers = [ROOT / 'lib/runtime/async/composed.c', ROOT / 'lib/runtime/platform/text-posix.c']
	links = []
	for provider in providers:
		obj = e.output / (provider.stem + '.o')
		e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', provider, '-o', obj])
		links += ['--link-object', obj]
		e.files(obj)
	for level in ['O0', 'O1', 'O2']:
		product = e.output / ('bridge-' + level)
		e.run([e.compiler, '-' + level, *sources, '--vapi', vapis[0], *links, '--link-library', 'pthread', '-o', product])
		e.run([product], stdout='', timeout=15)
		symbols = e.run(['nm', product]).stdout
		assert 'pthread_create' in symbols
		assert not any(name in symbols for name in ['io_uring_', 'astra_async_linux_', 'astra_context17_', 'g_object_', 'g_signal_'])
		e.files(product)
	e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', e.output / 'bridge-O2'], stdout='', contains='ERROR SUMMARY: 0 errors', timeout=45)
	for sanitizer in ['address', 'thread']:
		instrument(e, 'virtual-bridge', sources, providers, '', sanitizer, vapis=vapis)
	e.files(*sources, *providers, *vapis, Path(__file__))
	for name in ['virtual.h', 'provider.h', 'task-core17.c', 'task-api17.c', 'worker17.c']:
		e.files(ROOT / 'lib/runtime/async' / name)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
