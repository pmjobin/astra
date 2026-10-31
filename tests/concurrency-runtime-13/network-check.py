# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real kernel loopback activity and byte-exact independent C peers."""
from pathlib import Path
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
from sanitizers import instrument


def main(compiler, output):
	e = Evidence(compiler, output, 'concurrency-network')
	here = Path(__file__).parent
	common = [ROOT / 'lib/astra/hosted/network.astra', ROOT / 'lib/astra/async/threaded.astra', ROOT / 'lib/astra/base/errors.astra']
	base_providers = [ROOT / 'lib/runtime/async/threaded.c', ROOT / 'lib/runtime/platform/text-posix.c', ROOT / 'lib/runtime/platform/network-posix.c', here / 'network-oracle.c']
	flags = ['-Wl,--wrap=' + name for name in ['socket', 'accept4', 'close', 'send', 'recv']]
	cases = [
		('tcp', 'network-entry.c', [], [], 'TCP: two concurrent sessions, eight exact binary frames, backpressure, half-close, five exact closes\n'),
		('udp', 'udp-entry.c', [here / 'udp-oracle.c'], [], 'UDP: two producers, exact endpoints, empty/max/delayed datagrams, checked truncation and limits, three exact closes\n'),
		('lifetimes', 'network-lifetime-entry.c', [here / 'network-lifetime-oracle.c'], ['-Wl,--wrap=astra_async_complete'], 'network lifetime: deadline, cold/pending/completed cancellation, shutdown drain, five exact closes\n'),
	]
	for name, entry, extra, extra_flags, expected in cases:
		astra = [here / ('network-' + name + '.astra'), *common]
		providers = [*base_providers, *extra]
		case_flags = [*flags, *extra_flags]
		for level in ['O0', 'O1', 'O2']:
			obj, product = e.output / (name + '-' + level + '.o'), e.output / (name + '-' + level)
			e.run([e.compiler, '-' + level, '-c', *astra, '-o', obj])
			e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, here / entry, *case_flags, '-o', product])
			e.run([product], stdout=expected, timeout=45)
			e.run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], stdout=expected, contains='ERROR SUMMARY: 0 errors', timeout=60)
			e.files(obj, product)
		for sanitizer in ['address', 'thread']:
			instrument(e, name, astra, providers, expected, sanitizer, case_flags)
		trace = e.output / (name + '-kernel.strace')
		e.run(['strace', '-f', '-o', trace, '-e', 'trace=socket,bind,listen,connect,accept4,sendto,recvfrom,recvmsg,shutdown,close,poll', e.output / (name + '-O2')], stdout=expected, timeout=45)
		observed = trace.read_text()
		required = ['socket(', 'bind(']
		if name != 'lifetimes': required += ['sendto(']
		required += ['listen(', 'connect(', 'accept4(', 'recvfrom(', 'shutdown(', 'EAGAIN'] if name == 'tcp' else ['recvmsg(', 'MSG_TRUNC']
		for syscall in required:
			assert syscall in observed, syscall
		e.files(*astra, *providers, here / entry, Path(__file__), trace)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
