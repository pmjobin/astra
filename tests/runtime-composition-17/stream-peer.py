#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent framed client and byte/file oracle for streaming application A."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import resource
import select
import signal
import socket
import struct
import subprocess
import time


def exact(connection, count):
	result = bytearray()
	while len(result) < count:
		part = connection.recv(count - len(result))
		assert part, (len(result), count)
		result.extend(part)
	return bytes(result)


def expected_frames(compute=True, frame_limit=4093, transform_bias=17):
	frames = [bytes((i * 37 + sequence * 23 + i // 53) % 256 for i in range(min(size, frame_limit))) for sequence, size in enumerate([4093, 3079, 257, 1021, 4093, 997, 31, 1979])]
	digests, output = [], bytearray()
	for sequence, data in enumerate(frames):
		digest = sequence + 17
		if compute:
			for index in range(2000003): digest = (digest * 19 + data[index % len(data)] + index % 251) % 65521
		digests.append(digest)
		output.extend((byte + sequence % 31 + transform_bias) % 256 for byte in data)
	return frames, digests, bytes(output)


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--product', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--receipt', type=Path, required=True)
	parser.add_argument('--family', choices=['4', '6'], default='4')
	parser.add_argument('--valgrind', action='store_true')
	parser.add_argument('--frame-limit', type=int, default=4093)
	parser.add_argument('--transform-bias', type=int, default=17)
	args = parser.parse_args()
	product = args.product.resolve(strict=True); output = args.output.resolve()
	args.receipt.parent.mkdir(parents=True, exist_ok=True)
	family, address = (socket.AF_INET, '127.0.0.1') if args.family == '4' else (socket.AF_INET6, '::1')
	assert 31 <= args.frame_limit <= 4093 and 0 <= args.transform_bias <= 255
	frames, digests, expected = expected_frames(frame_limit=args.frame_limit, transform_bias=args.transform_bias)
	command = [str(product), address, args.family, str(output)]
	if args.valgrind: command = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *command]
	receipt = dict(command=command, product_sha256=hashlib.sha256(product.read_bytes()).hexdigest(), frame_sizes=[len(data) for data in frames], digests=digests, expected_output_sha256=hashlib.sha256(expected).hexdigest(), progress=[])
	start = time.monotonic()
	process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
	try:
		assert select.select([process.stdout], [], [], 10)[0], 'application readiness deadline'
		first = process.stdout.readline(); assert first, 'application exited before readiness'
		ports = json.loads(first); assert ports['pid'] == process.pid
		receipt['ports'] = ports
		with socket.socket(family, socket.SOCK_STREAM) as tcp, socket.socket(family, socket.SOCK_DGRAM) as udp:
			tcp.settimeout(20); udp.settimeout(5)
			tcp.connect((address, ports['tcp'])); udp.bind((address, 0))
			receipt['tcp_local'] = tcp.getsockname(); receipt['tcp_peer'] = tcp.getpeername()
			for packet in [b'', b'X', b'Q' * 127]: udp.sendto(packet, (address, ports['udp']))
			udp.sendto(b'Q', (address, ports['udp'])); recovered, peer = udp.recvfrom(64)
			assert struct.unpack('<4I', recovered) == (17, 0, 0, 0)
			assert peer[0] == address and peer[1] == ports['udp']
			receipt['malformed_udp_recovered'] = True
			for sequence, data in enumerate(frames):
				header = struct.pack('<I', len(data))
				for fragment in [header[:1], header[1:3], header[3:]]: tcp.sendall(fragment)
				step = 127 + sequence % 5 * 37
				for offset in range(0, len(data), step):
					tcp.sendall(data[offset:offset + step])
					if offset % (step * 7) == 0: time.sleep(0.001)
				udp.sendto(b'Q', (address, ports['udp'])); reply, peer = udp.recvfrom(64)
				progress = struct.unpack('<4I', reply)
				assert progress[0] == 17 and progress[1] <= len(frames) and progress[2] <= len(expected)
				assert peer[0] == address and peer[1] == ports['udp']
				receipt['progress'].append(dict(sequence=sequence, values=progress, peer=peer))
			tcp.sendall(struct.pack('<I', 0)); tcp.shutdown(socket.SHUT_WR)
			answer = struct.unpack('<4I', exact(tcp, 16))
			assert answer == (17, len(frames), len(expected), sum(digests) % 65521), answer
			assert tcp.recv(1) == b''
			receipt['answer'] = answer
		out, err = process.communicate(timeout=20)
		receipt.update(exit=process.returncode, stdout=first + out, stderr=err)
		assert process.returncode == 0, receipt
		if args.valgrind: assert 'ERROR SUMMARY: 0 errors' in err
		assert output.read_bytes() == expected, 'independent transformed file mismatch'
		receipt['actual_output_sha256'] = hashlib.sha256(output.read_bytes()).hexdigest()
		assert hashlib.sha256(product.read_bytes()).hexdigest() == receipt['product_sha256']
		receipt['status'] = 'PASS'
	finally:
		if process.poll() is None:
			os.killpg(process.pid, signal.SIGTERM)
			try: out, err = process.communicate(timeout=10)
			except subprocess.TimeoutExpired:
				os.killpg(process.pid, signal.SIGKILL); out, err = process.communicate(timeout=3)
			receipt.update(exit=process.returncode, stdout=out, stderr=err)
		elif 'exit' not in receipt:
			out, err = process.communicate(); receipt.update(exit=process.returncode, stdout=out, stderr=err)
		receipt.update(seconds=time.monotonic() - start, maxrss_kib=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss)
		args.receipt.write_text(json.dumps(receipt, indent=2) + '\n')
	print('PASS: streaming peer, exact ordered transformed file and TCP/UDP progress')


if __name__ == '__main__':
	main()
