#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent socket clients exercise actual generated endpoint servers."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import socket
import struct
import sys
import time
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence
sys.path.insert(0, str(ROOT / 'tests/concurrency-runtime-13'))
from sanitizers import instrument


def receive(connection, size):
	data = bytearray()
	while len(data) < size:
		part = connection.recv(min(619, size - len(data)))
		assert part, (len(data), size)
		data.extend(part)
	return bytes(data)


def client(address, family, ports, mode):
	data = bytes((i * 19 + i // 37) % 256 for i in range(65527))
	with socket.socket(family, socket.SOCK_STREAM) as tcp:
		tcp.settimeout(10); tcp.connect((address, ports['tcp']))
		local, remote = tcp.getsockname(), tcp.getpeername()
		assert remote[0] == address and remote[1] == ports['tcp']
		if mode == 0:
			for byte in struct.pack('<I', 8193): tcp.sendall(bytes([byte]))
			for offset in range(0, 8193, 127): tcp.sendall(data[offset:min(offset + 127, 8193)])
			tcp.shutdown(socket.SHUT_WR)
			assert receive(tcp, 8193) == data[:8193] and tcp.recv(1) == b''
		elif mode == 1:
			tcp.sendall(b'xx'); tcp.shutdown(socket.SHUT_WR)
			assert tcp.recv(1) == b''
		elif mode == 2:
			start = time.monotonic(); assert tcp.recv(1) == b''
			assert time.monotonic() - start >= 0.09
		elif mode == 3:
			tcp.sendall(b'xx'); time.sleep(0.03)
			tcp.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack('ii', 1, 0))
		elif mode == 4:
			time.sleep(0.15)
			expected = (data[:65507] * 17)[:1048577]
			assert receive(tcp, len(expected)) == expected and tcp.recv(1) == b''
	observations = [dict(protocol='tcp', local=local, peer=remote, scenario=mode)]
	if mode == 0:
		with socket.socket(family, socket.SOCK_DGRAM) as udp:
			udp.settimeout(10); udp.bind((address, 0))
			maximum = 65507 if family == socket.AF_INET else 65527
			for index, size in enumerate([0, 4097, maximum, 4097]):
				assert udp.sendto(data[:size], (address, ports['udp'])) == size
				answer, peer = udp.recvfrom(65535); expected = data[:19] if index == 3 else data[:size]
				assert answer == expected and peer[0] == address and peer[1] == ports['udp']
				observations.append(dict(protocol='udp', sent=size, received=len(answer), peer=peer, sha256=hashlib.sha256(answer).hexdigest()))
	return observations


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-endpoint-server')
	here = Path(__file__).resolve().parent; build = Path(compiler).resolve().parent
	sources = [here / 'endpoint-server.astra', ROOT / 'lib/astra/hosted/network.astra', ROOT / 'lib/astra/base/errors.astra']
	providers = [ROOT / 'lib/runtime/platform/network-posix.c', ROOT / 'lib/runtime/runtime/context-17.c', here / 'endpoint-server-oracle.c']
	vapi = ROOT / 'lib/bindings/memory/contexts.vapi'
	wrappers = ['-Wl,--wrap=' + name for name in ['astra_net_accept_from', 'astra_context17_allocate_mode', 'astra_context17_release_origin_checked']]
	e.files(*sources, *providers, vapi, Path(__file__), ROOT / 'tests/concurrency-runtime-13/sanitizers.py')
	e.data['exchanges'] = []; e.save()
	expected = 'endpoint server: typed peer, bounded context bytes, progress/error contract and exact FD retirement\n'
	def exercise(product, label, environment=None, prefix=()):
		for family, address, spelling in [(socket.AF_INET, '127.0.0.1', '4'), (socket.AF_INET6, '::1', '6')]:
			for mode in range(5):
				ready = e.output / ('ready-' + label + '-' + spelling + '-' + str(mode) + '.json')
				ready.unlink(missing_ok=True)
				with ThreadPoolExecutor(max_workers=1) as pool:
					server = pool.submit(e.run, [*prefix, product, address, spelling], contains=expected.strip(), timeout=45, env=dict(environment or {}, M17_SERVER_READY_PATH=str(ready), M17_SERVER_MODE=str(mode)))
					deadline = time.monotonic() + 10
					while not ready.exists():
						if server.done(): server.result(); raise AssertionError('server exited without ready endpoints')
						assert time.monotonic() < deadline, 'server readiness deadline'
						time.sleep(0.005)
					ports = json.loads(ready.read_text())
					observations = client(address, family, ports, mode)
					result = server.result(timeout=10)
				if prefix: assert 'ERROR SUMMARY: 0 errors' in result.stderr
				e.data['exchanges'].append(dict(profile=label, family=spelling, ports=ports, observations=observations, metrics=result.stdout)); e.save(); e.files(ready)
	for level in ['0', '1', '2']:
		obj, product = [e.output / ('server-O' + level + suffix) for suffix in ['.o', '']]
		e.run([e.compiler, '-O' + level, '--entry-object', *sources, '--vapi', vapi, '-o', obj])
		e.run(['cc', '-O2', '-g', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', obj, *providers, build / 'lib/astra/text-posix.o', build / 'lib/astra/args-posix.o', *wrappers, '-o', product])
		exercise(product, 'O' + level)
		e.files(obj, product)
	exercise(e.output / 'server-O2', 'valgrind', prefix=['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all'])
	for sanitizer in ['address', 'thread']:
		instrument(e, 'endpoint-server', sources, [*providers, ROOT / 'lib/runtime/platform/text-posix.c', ROOT / 'lib/runtime/platform/args-posix.c'], expected, sanitizer, link_flags=wrappers, vapis=[vapi], execute=lambda product, environment: exercise(product, sanitizer, environment))
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
