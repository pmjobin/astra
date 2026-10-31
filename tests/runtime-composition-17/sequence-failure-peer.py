#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Live signal and real file-failure peers for frozen triple-range B3."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import random
import resource
import select
import signal
import socket
import struct
import subprocess
import threading
import time


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--product', type=Path, required=True); p.add_argument('--output', type=Path, required=True)
	p.add_argument('--receipt', type=Path, required=True); p.add_argument('--family', choices=['4', '6'], default='4')
	p.add_argument('--mode', choices=['cpu', 'io', 'bad-fd', 'eof'], required=True)
	a = p.parse_args(); product = a.product.resolve(strict=True); data = a.output.resolve(); data.parent.mkdir(parents=True, exist_ok=True)
	a.receipt.parent.mkdir(parents=True, exist_ok=True); data.write_bytes(random.Random(2575218845).randbytes(48017))
	family, address = (socket.AF_INET, '127.0.0.1') if a.family == '4' else (socket.AF_INET6, '::1')
	command = [str(product), address, a.family, str(data)]
	receipt = dict(command=command, mode=a.mode, freeze=3, product_sha256=hashlib.sha256(product.read_bytes()).hexdigest())
	process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True, env=dict(os.environ, M17_SEQUENCE_MODE=a.mode, ASTRA_SEQUENCE_EVENTS='1'))
	output, errors, readers, sockets = [], [], [], []; gate = threading.Event(); start = time.monotonic()
	def collect(pipe, target):
		for line in pipe:
			target.append(line)
			if target is output:
				try: value = json.loads(line)
				except ValueError: continue
				if value.get('gate') == ('cpu' if a.mode == 'cpu' else 'io-submitted'): gate.set()
	try:
		assert select.select([process.stdout], [], [], 15)[0], 'sequence readiness deadline'
		first = process.stdout.readline(); output.append(first); ports = json.loads(first); assert ports['pid'] == process.pid
		receipt['ports'] = ports
		for pipe, target in [(process.stdout, output), (process.stderr, errors)]:
			t = threading.Thread(target=collect, args=(pipe, target)); t.start(); readers.append(t)
		if a.mode == 'eof': data.write_bytes(b'')
		for i in range(3):
			s = socket.socket(family, socket.SOCK_STREAM); s.settimeout(15); s.connect((address, ports['tcp'])); sockets.append(s)
		for i, s in enumerate(sockets): s.sendall(struct.pack('<8I', 10+i, 101+i*3001, 2309, 13013, 2203, 28013, 2207, 0))
		if a.mode in ['cpu', 'io']:
			assert gate.wait(12), 'actual worker/IO lifecycle gate was not reached'
			os.kill(process.pid, signal.SIGINT); receipt['signal_after_gate'] = 'worker-executing' if a.mode == 'cpu' else 'real-io-submitted'
		process.wait(timeout=30)
		for t in readers: t.join(5); assert not t.is_alive()
		receipt.update(exit=process.returncode, stdout=''.join(output), stderr=''.join(errors))
		assert process.returncode == (130 if a.mode in ['cpu', 'io'] else 1), receipt
		rows = [json.loads(line) for line in receipt['stdout'].splitlines()]
		observed = [row for row in rows if 'observed_profile' in row]; assert len(observed) == 1
		x = observed[0]; assert x['io_submitted'] == x['io_retired'] and x['allocations'] == x['releases']
		arenas = [row for row in rows if 'arena_contexts' in row]; assert len(arenas) == 1 and arenas[0]['opened'] == arenas[0]['disposed']
		for row in arenas[0]['arena_contexts']: assert row['allocations'] == row['releases'] and row['peak_live_bytes'] <= row['arena_bytes']
		if a.mode in ['bad-fd', 'eof']: assert 'sequence:' in receipt['stderr']
		assert hashlib.sha256(product.read_bytes()).hexdigest() == receipt['product_sha256']
		receipt['status'] = 'PASS'; receipt['observed'] = x
	finally:
		if process.poll() is None:
			os.killpg(process.pid, signal.SIGTERM)
			try: process.wait(timeout=10)
			except subprocess.TimeoutExpired: os.killpg(process.pid, signal.SIGKILL); process.wait(timeout=3)
		for s in sockets: s.close()
		for t in readers: t.join(5)
		receipt.update(exit=process.returncode, stdout=''.join(output), stderr=''.join(errors), seconds=time.monotonic()-start)
		a.receipt.write_text(json.dumps(receipt, indent=2)+'\n')
	print('PASS: sequence ' + a.mode + ', observed outcome and exact joined conservation')


if __name__ == '__main__': main()
