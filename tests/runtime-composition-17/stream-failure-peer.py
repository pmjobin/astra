#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent malformed-stream and live-signal clients; never drive a task."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import select
import signal
import socket
import struct
import subprocess
import threading
import time


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--product', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--receipt', type=Path, required=True)
	parser.add_argument('--family', choices=['4', '6'], default='4')
	parser.add_argument('--mode', choices=['cancel', 'truncate', 'oversize', 'file-error'], required=True)
	args = parser.parse_args()
	product = args.product.resolve(strict=True); destination = args.output.resolve()
	args.receipt.parent.mkdir(parents=True, exist_ok=True)
	if args.mode == 'file-error': destination.mkdir(exist_ok=True)
	family, address = (socket.AF_INET, '127.0.0.1') if args.family == '4' else (socket.AF_INET6, '::1')
	command = [str(product), address, args.family, str(destination)]
	environment = dict(os.environ, M17_STREAM_MODE=args.mode)
	if args.mode == 'cancel': environment.update(ASTRA_STREAM_EVENTS='1', M17_STREAM_TRACE='1')
	result = dict(command=command, mode=args.mode, product_sha256=hashlib.sha256(product.read_bytes()).hexdigest())
	process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True, env=environment)
	output, errors = [], []; completion = threading.Event(); readers = []
	def collect(pipe, target):
		for line in pipe:
			target.append(line)
			if target is output:
				try: value = json.loads(line)
				except json.JSONDecodeError: continue
				if value.get('file_completion', 0) > 0 and value.get('cpu_active', 0) > 0: completion.set()
	start = time.monotonic()
	try:
		assert select.select([process.stdout], [], [], 10)[0], 'application readiness deadline'
		first = process.stdout.readline(); output.append(first)
		ports = json.loads(first); assert ports['pid'] == process.pid
		result['ports'] = ports
		for pipe, target in [(process.stdout, output), (process.stderr, errors)]:
			reader = threading.Thread(target=collect, args=(pipe, target)); reader.start(); readers.append(reader)
		with socket.socket(family, socket.SOCK_STREAM) as tcp:
			tcp.settimeout(10); tcp.connect((address, ports['tcp']))
			if args.mode == 'truncate': tcp.sendall(struct.pack('<I', 4093) + bytes(range(127))); tcp.shutdown(socket.SHUT_WR)
			if args.mode == 'oversize': tcp.sendall(struct.pack('<I', 4094))
			if args.mode == 'cancel':
				path = Path(__file__).with_name('stream-peer.py')
				spec = importlib.util.spec_from_file_location('stream_peer', path); peer = importlib.util.module_from_spec(spec); spec.loader.exec_module(peer)
				frames, _, _ = peer.expected_frames(compute=False)
				for frame in frames: tcp.sendall(struct.pack('<I', len(frame)) + frame)
				tcp.sendall(struct.pack('<I', 0))
				assert completion.wait(10), 'real file completion during CPU activity was not observed'
				os.kill(process.pid, signal.SIGINT)
				result['signal'] = 'SIGINT after actual file completion with CPU active'
			process.wait(timeout=20)
		for reader in readers: reader.join(timeout=3); assert not reader.is_alive()
		expected = 130 if args.mode == 'cancel' else 1
		result.update(exit=process.returncode, stdout=''.join(output), stderr=''.join(errors))
		assert process.returncode == expected, result
		if args.mode != 'cancel': assert 'stream:' in result['stderr']
		assert hashlib.sha256(product.read_bytes()).hexdigest() == result['product_sha256']
		result['status'] = 'PASS'
	finally:
		if process.poll() is None:
			os.killpg(process.pid, signal.SIGTERM)
			try: process.wait(timeout=10)
			except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=3)
		for reader in readers: reader.join(timeout=3)
		result.update(exit=process.returncode, stdout=''.join(output), stderr=''.join(errors), seconds=time.monotonic() - start)
		args.receipt.write_text(json.dumps(result, indent=2) + '\n')
	print('PASS: stream ' + args.mode + ', observed outcome and complete resource conservation')


if __name__ == '__main__':
	main()
