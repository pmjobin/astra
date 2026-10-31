#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent weighted range protocol with shortest-path edit-graph oracle."""
from pathlib import Path
from collections import Counter
from functools import lru_cache
import heapq
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


def exact(connection, count):
	data = bytearray()
	while len(data) < count:
		part = connection.recv(count - len(data)); assert part, (len(data), count)
		data.extend(part)
	return bytes(data)


@lru_cache(maxsize=16)
def frontier(reference, comparison, costs):
	# Independent shortest paths over the edit graph. No in-place DP update,
	# shared source generator or service implementation is used here.
	insertion, deletion, substitution = costs
	width = len(reference) + 1; height = len(comparison) + 1
	distance = [1 << 30] * (width * height); distance[0] = 0
	queue = [(0, 0)]; remaining = width
	while queue and remaining:
		cost, node = heapq.heappop(queue)
		if distance[node] != cost: continue
		row, column = divmod(node, width)
		if row == height - 1: remaining -= 1
		edges = []
		if column + 1 < width: edges.append((node + 1, deletion))
		if row + 1 < height: edges.append((node + width, insertion))
		if column + 1 < width and row + 1 < height:
			edges.append((node + width + 1, 0 if reference[column] == comparison[row] else substitution))
		for target, weight in edges:
			value = cost + weight
			if value < distance[target]: distance[target] = value; heapq.heappush(queue, (value, target))
	assert remaining == 0
	return tuple(distance[(height - 1) * width:])


def oracle(data, triple, costs, identity, cached):
	a, n, b, m, c, k = triple
	reference, left, right = data[a:a+n], data[b:b+m], data[c:c+k]
	left_profile, right_profile = frontier(reference, left, costs), frontier(reference, right, costs)
	all_bytes = reference + left + right; total = sum(all_bytes)
	witness = sum((total + left_profile[-1] * 3 + right_profile[-1] * 5 + costs[0] * 7 + costs[1] * 13 + costs[2] * 17 + i * 11) % 251 for i in range(32))
	return (84, identity, 0, cached, 4, 4, *triple, *costs, len(all_bytes), total, sum(x*x for x in all_bytes),
		left_profile[-1], right_profile[-1], left_profile[n//3], right_profile[(2*n)//3], n+1, witness)


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	assert frontier(b'', b'abc', (2, 3, 4)) == (6,)
	assert frontier(b'abc', b'', (2, 3, 4)) == (0, 3, 6, 9)
	assert frontier(b'abc', b'abc', (2, 3, 4))[-1] == 0
	assert frontier(b'a', b'b', (1, 2, 7))[-1] == 3
	assert frontier(b'a', b'b', (4, 5, 2))[-1] == 2

	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--product', type=Path, required=True); p.add_argument('--output', type=Path, required=True)
	p.add_argument('--receipt', type=Path, required=True); p.add_argument('--family', choices=['4', '6'], default='4')
	p.add_argument('--valgrind', action='store_true'); p.add_argument('--allow-serialized-tools', action='store_true')
	a = p.parse_args(); product = a.product.resolve(strict=True); output = a.output.resolve(); output.parent.mkdir(parents=True, exist_ok=True)
	a.receipt.parent.mkdir(parents=True, exist_ok=True)
	data = random.Random(1776966140).randbytes(48017); output.write_bytes(data)
	family, address = (socket.AF_INET, '127.0.0.1') if a.family == '4' else (socket.AF_INET6, '::1')
	cmd = [str(product), address, a.family, str(output)]
	if a.valgrind: cmd = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *cmd]
	receipt = dict(command=cmd, product_sha256=hashlib.sha256(product.read_bytes()).hexdigest(), input_sha256=hashlib.sha256(data).hexdigest(), seed=1776966140, freeze=4, challenge_complete=False, progress=[], replies=[])
	start = time.monotonic(); proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True, env=dict(os.environ, ASTRA_BRAID_EVENTS='1'))
	sockets = []; threads = []; errors = []; gate = threading.Barrier(3, timeout=40); end = threading.Event(); done = [threading.Event() for _ in range(3)]
	try:
		assert select.select([proc.stdout], [], [], 15)[0], 'query readiness deadline'
		first = proc.stdout.readline(); ports = json.loads(first); assert ports['pid'] == proc.pid
		receipt['ports'] = ports
		for _ in range(3):
			s = socket.socket(family, socket.SOCK_STREAM); s.settimeout(40); s.connect((address, ports['tcp'])); sockets.append(s)
		pairs = [(101, 347, 13013, 331, 28013, 359), (3079, 383, 19001, 367, 32003, 379), (6007, 401, 23003, 389, 37009, 397)]
		weights = [(2, 3, 4), (3, 1, 5), (1, 4, 2)]
		def client(index):
			try:
				s = sockets[index]; pair = pairs[index]
				for turn in range(8):
					gate.wait(); identity = (turn + 1) * 10 + index
					mode = 1 if turn == 4 else 0
					costs = weights[index] if turn < 2 else (weights[index][1], weights[index][0], weights[index][2] + 1)
					if turn == 6: costs = (0, costs[1], costs[2])
					if turn == 7: costs = (costs[0], costs[1], 8)
					request = pair if turn != 5 else (48000, 101, 17, 31, 23, 19)
					frame = struct.pack('<11I', identity, *request, mode, *costs)
					for part in [frame[:1], frame[1:9], frame[9:17], frame[17:]]: s.sendall(part)
					answer = struct.unpack('<24I', exact(s, 96))
					expected = oracle(data, pair, costs, identity, int(turn in [1, 3])) if turn < 4 else (84, identity, 2 if turn == 4 else 1, *([0] * 21))
					assert answer == expected, (index, turn, answer, expected)
					receipt['replies'].append(dict(client=index, turn=turn, values=answer))
				done[index].set(); assert end.wait(40)
				s.sendall(bytes(44)); s.shutdown(socket.SHUT_WR); assert s.recv(1) == b''
			except BaseException as failure:
				errors.append(repr(failure)); gate.abort(); done[index].set()
		for i in range(3):
			t = threading.Thread(target=client, args=(i,)); threads.append(t); t.start()
		with socket.socket(family, socket.SOCK_DGRAM) as udp:
			udp.settimeout(10); udp.bind((address, 0))
			for message in [b'', b'X', b'QQQ']: udp.sendto(message, (address, ports['udp']))
			deadline = time.monotonic() + 45
			while True:
				assert time.monotonic() < deadline, 'query progress deadline'
				udp.sendto(b'Q', (address, ports['udp'])); reply, peer = udp.recvfrom(128)
				values = struct.unpack('<6I', reply); assert values[0] == 84 and peer[:2] == (address, ports['udp'])
				receipt['progress'].append(list(values))
				if all(d.is_set() for d in done): break
				time.sleep(0.005)
			assert not errors, errors
			assert values == (84, 6, 9, min(6, int(os.environ.get('ASTRA_BRAID_CACHE', '7'))), 12, 0), values
		end.set()
		for t in threads: t.join(15); assert not t.is_alive()
		assert not errors, errors
		out, err = proc.communicate(timeout=25); receipt.update(exit=proc.returncode, stdout=first+out, stderr=err)
		assert proc.returncode == 0, receipt
		rows = [json.loads(line) for line in receipt['stdout'].splitlines()]
		metrics = [r for r in rows if 'cpu_peak' in r]; assert len(metrics) == 1
		m = metrics[0]; assert m['analyses'] == 6 and m['reads'] == 9 and m['responses'] == 24 and m['refusals'] == 3
		assert m['tickets'] == m['retired_tickets'] == 9 and m['entries'] == m['retired_entries'] == 6
		assert m['cpu_peak'] == 2 or a.allow_serialized_tools and m['cpu_peak'] == 1, m
		providers = [r for r in rows if 'arena_contexts' in r]; assert len(providers) == 1
		pr = providers[0]; assert pr['opened'] == pr['disposed'] == 7 and pr['guard_bytes_per_allocation'] == 64
		assert {x['identity'] for x in pr['arena_contexts']} == {11, 12, 13, 40, 41, 61, 62}
		for c in pr['arena_contexts']:
			assert c['allocations'] == c['releases'] and c['peak_live_bytes'] <= c['arena_bytes']
			assert c['buddy_splits'] == c['buddy_coalesces'] and c['peak_reserved_live_bytes'] <= c['buddy_reserved_bytes'] and c['refusals'] == 0
		leases = [r for r in rows if r.get('event') == 11]; assert len(leases) == 1 and leases[0]['identity'] + leases[0]['value'] < 2
		if a.valgrind: assert 'ERROR SUMMARY: 0 errors' in err and 'All heap blocks were freed' in err
		assert output.read_bytes() == data and hashlib.sha256(product.read_bytes()).hexdigest() == receipt['product_sha256']
		receipt['metrics'] = m; receipt['status'] = 'PASS'
	finally:
		end.set()
		if proc.poll() is None:
			os.killpg(proc.pid, signal.SIGTERM)
			try: out, err = proc.communicate(timeout=10)
			except subprocess.TimeoutExpired: os.killpg(proc.pid, signal.SIGKILL); out, err = proc.communicate(timeout=3)
			receipt.update(exit=proc.returncode, stdout=out, stderr=err)
		elif 'exit' not in receipt:
			out, err = proc.communicate(); receipt.update(exit=proc.returncode, stdout=out, stderr=err)
		for s in sockets: s.close()
		for t in threads: t.join(5)
		receipt['errors'] = errors; receipt['seconds'] = time.monotonic() - start
		a.receipt.write_text(json.dumps(receipt, indent=2)+'\n')
	print('PASS: weighted range edit, independent shortest paths, cache reuse and TCP/UDP progress')


if __name__ == '__main__': main()
