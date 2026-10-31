#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Public Astra endpoints against independent platform socket peers."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import hashlib
import json
import os
import socket
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def oracle(tcp, udp):
	expected = bytes((i * 19 + i // 37) % 256 for i in range(8193))
	connection, peer = tcp.accept()
	with connection:
		connection.settimeout(10)
		data = bytearray()
		while len(data) < len(expected):
			part = connection.recv(619)
			assert part, 'unexpected EOF'
			data.extend(part)
		assert data == expected and connection.recv(1) == b''
		for start in range(0, len(data), 113):
			connection.sendall(data[start:start + 113])
		connection.shutdown(socket.SHUT_WR)
	observations = [{'protocol': 'tcp', 'peer': peer, 'bytes': len(data),
		'sha256': hashlib.sha256(data).hexdigest()}]
	for size in [0, 4097, 4097]:
		data, peer = udp.recvfrom(65535)
		assert data == expected[:size]
		assert udp.sendto(data, peer) == size
		observations.append({'protocol': 'udp', 'peer': peer, 'bytes': size,
			'sha256': hashlib.sha256(data).hexdigest()})
	return observations


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-endpoints')
	here = Path(__file__).resolve().parent
	build = Path(compiler).resolve().parent
	common = [ROOT / 'lib/astra/hosted/network.astra', ROOT / 'lib/astra/base/errors.astra']
	provider = ROOT / 'lib/runtime/platform/network-posix.c'
	network = e.output / 'network.o'
	e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c', provider, '-o', network])
	e.data['exchanges'] = []
	for level in ['O0', 'O1', 'O2']:
		for source, observer in [('endpoints', 'endpoint-oracle'), ('endpoint-client', 'endpoint-config')]:
			product = e.output / (source + '-' + level)
			objects = [network, build / 'lib/astra/text-posix.o']
			if source == 'endpoint-client': objects += [build / 'lib/astra/args-posix.o']
			obj = e.output / (observer + '.o')
			e.run(['cc', '-std=c11', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c', here / (observer + '.c'), '-o', obj])
			links = [item for path in [*objects, obj] for item in ['--link-object', path]]
			e.run([e.compiler, '-' + level, here / (source + '.astra'), *common, *links, '-o', product])
			e.files(product, obj, here / (source + '.astra'), here / (observer + '.c'))
			if source == 'endpoints': e.run([product])
		for family, address, spelling in [(socket.AF_INET, '127.0.0.1', '4'), (socket.AF_INET6, '::1', '6')]:
			with socket.socket(family, socket.SOCK_STREAM) as tcp, socket.socket(family, socket.SOCK_DGRAM) as udp:
				for listener in (tcp, udp):
					listener.settimeout(10)
					listener.bind((address, 0))
				tcp.listen(1)
				with ThreadPoolExecutor(max_workers=1) as pool:
					peer = pool.submit(oracle, tcp, udp)
					e.run([e.output / ('endpoint-client-' + level), address, spelling], timeout=12,
						env={'M17_TCP_PORT': str(tcp.getsockname()[1]), 'M17_UDP_PORT': str(udp.getsockname()[1])})
					e.data['exchanges'].append({'level': level, 'family': spelling, 'peer': address,
						'tcp_port': tcp.getsockname()[1], 'udp_port': udp.getsockname()[1],
						'observations': peer.result(timeout=2)})
					e.save()
	e.files(*common, provider, provider.with_suffix('.h'), Path(__file__), network)
	e.complete()


if __name__ == '__main__':
	main(*sys.argv[1:])
