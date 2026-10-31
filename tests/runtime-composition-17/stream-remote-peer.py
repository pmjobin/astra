#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent client for A in the already approved separate peer namespace."""
import argparse
import importlib.util
import json
from pathlib import Path
import socket
import struct
import sys
import time
sys.dont_write_bytecode = True


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--address', required=True)
	parser.add_argument('--bind', required=True)
	parser.add_argument('--family', choices=['4', '6'], required=True)
	parser.add_argument('--tcp', type=int, required=True)
	parser.add_argument('--udp', type=int, required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--receipt', type=Path, required=True)
	args = parser.parse_args()
	spec = importlib.util.spec_from_file_location('stream_peer', Path(__file__).with_name('stream-peer.py'))
	oracle = importlib.util.module_from_spec(spec); spec.loader.exec_module(oracle)
	frames, digests, expected = oracle.expected_frames()
	family = socket.AF_INET if args.family == '4' else socket.AF_INET6
	result = dict(namespace=Path('/proc/self/ns/net').readlink().as_posix(), progress=[])
	with socket.socket(family, socket.SOCK_STREAM) as tcp, socket.socket(family, socket.SOCK_DGRAM) as udp:
		tcp.settimeout(20); udp.settimeout(5)
		tcp.bind((args.bind, 0)); udp.bind((args.bind, 0)); tcp.connect((args.address, args.tcp))
		result.update(tcp_local=tcp.getsockname(), tcp_peer=tcp.getpeername(), udp_local=udp.getsockname())
		for packet in [b'', b'X', b'Q' * 127]: udp.sendto(packet, (args.address, args.udp))
		udp.sendto(b'Q', (args.address, args.udp)); data, peer = udp.recvfrom(64)
		assert struct.unpack('<4I', data) == (17, 0, 0, 0) and peer[0] == args.address and peer[1] == args.udp
		result['malformed_udp_recovered'] = True
		for sequence, data in enumerate(frames):
			header = struct.pack('<I', len(data))
			for part in [header[:1], header[1:3], header[3:]]: tcp.sendall(part)
			for offset in range(0, len(data), 151):
				tcp.sendall(data[offset:offset + 151])
				if offset % 1057 == 0: time.sleep(0.001)
			udp.sendto(b'Q', (args.address, args.udp)); data, peer = udp.recvfrom(64)
			status = struct.unpack('<4I', data)
			assert status[0] == 17 and status[1] <= 8 and status[2] <= len(expected)
			assert peer[0] == args.address and peer[1] == args.udp
			result['progress'].append(dict(values=status, peer=peer))
		tcp.sendall(struct.pack('<I', 0)); tcp.shutdown(socket.SHUT_WR)
		answer = struct.unpack('<4I', oracle.exact(tcp, 16))
		assert answer == (17, 8, len(expected), sum(digests) % 65521) and tcp.recv(1) == b''
		result['answer'] = answer
	assert args.output.read_bytes() == expected
	result['status'] = 'PASS'; args.receipt.write_text(json.dumps(result, indent=2) + '\n')
	print(json.dumps(result), flush=True)


if __name__ == '__main__':
	main()
