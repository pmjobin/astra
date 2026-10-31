#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent paired-range query protocol and distribution oracle (B2 regression)."""
from pathlib import Path
from collections import Counter
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


def oracle(data, pair, identity, cached):
	a, n, b, m = pair
	left, right = Counter(data[a:a+n]), Counter(data[b:b+m])
	joint = left + right
	ordered = sorted(joint.elements())
	count = n + m
	# Independent frequency-product algorithm; the service compares individual
	# pairs of source bytes and never uses this oracle's implementation.
	cross = sum(abs(x-y) * nx * ny for x, nx in left.items() for y, ny in right.items()) % 65521
	return (82, identity, 0, cached, 2, a, n, b, m, count,
		sum(x * nx for x, nx in joint.items()), sum(x*x*nx for x, nx in joint.items()), cross,
		ordered[0], ordered[(count-1)//4], ordered[(count-1)//2], ordered[((count-1)*3)//4], ordered[-1], joint[0], joint[255])


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--product', type=Path, required=True); p.add_argument('--output', type=Path, required=True)
	p.add_argument('--receipt', type=Path, required=True); p.add_argument('--family', choices=['4', '6'], default='4')
	p.add_argument('--valgrind', action='store_true'); p.add_argument('--allow-serialized-tools', action='store_true')
	a = p.parse_args(); product = a.product.resolve(strict=True); output = a.output.resolve(); output.parent.mkdir(parents=True, exist_ok=True)
	a.receipt.parent.mkdir(parents=True, exist_ok=True)
	data = random.Random(2290007590).randbytes(32011); output.write_bytes(data)
	family, address = (socket.AF_INET, '127.0.0.1') if a.family == '4' else (socket.AF_INET6, '::1')
	cmd = [str(product), address, a.family, str(output)]
	if a.valgrind: cmd = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *cmd]
	receipt = dict(command=cmd, product_sha256=hashlib.sha256(product.read_bytes()).hexdigest(), input_sha256=hashlib.sha256(data).hexdigest(), seed=2290007590, challenge_credit=False, progress=[], replies=[])
	start = time.monotonic(); proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True, env=dict(os.environ, ASTRA_QUERY_EVENTS='1'))
	sockets = []; threads = []; errors = []; gate = threading.Barrier(3, timeout=40); end = threading.Event(); done = [threading.Event() for _ in range(3)]
	try:
		assert select.select([proc.stdout], [], [], 15)[0], 'query readiness deadline'
		first = proc.stdout.readline(); ports = json.loads(first); assert ports['pid'] == proc.pid
		receipt['ports'] = ports
		for _ in range(3):
			s = socket.socket(family, socket.SOCK_STREAM); s.settimeout(40); s.connect((address, ports['tcp'])); sockets.append(s)
		pairs = [(101, 2801, 13013, 2539), (3079, 2719, 19001, 2609), (6007, 2897, 23003, 2503)]
		def client(index):
			try:
				s = sockets[index]; pair = pairs[index]
				for turn in range(4):
					gate.wait(); identity = (turn + 1) * 10 + index
					mode = 1 if turn == 2 else 0
					request = pair if turn != 3 else (32000, 101, 17, 31)
					frame = struct.pack('<6I', identity, *request, mode)
					for part in [frame[:1], frame[1:9], frame[9:17], frame[17:]]: s.sendall(part)
					answer = struct.unpack('<20I', exact(s, 80))
					expected = oracle(data, pair, identity, int(turn == 1)) if turn < 2 else (82, identity, 2 if turn == 2 else 1, *([0] * 17))
					assert answer == expected, (index, turn, answer, expected)
					receipt['replies'].append(dict(client=index, turn=turn, values=answer))
				done[index].set(); assert end.wait(40)
				s.sendall(bytes(24)); s.shutdown(socket.SHUT_WR); assert s.recv(1) == b''
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
				values = struct.unpack('<6I', reply); assert values[0] == 82 and peer[:2] == (address, ports['udp'])
				receipt['progress'].append(list(values))
				if all(d.is_set() for d in done): break
				time.sleep(0.005)
			assert not errors, errors
			assert values == (82, 3, 6, 3, 6, 0), values
		end.set()
		for t in threads: t.join(15); assert not t.is_alive()
		assert not errors, errors
		out, err = proc.communicate(timeout=25); receipt.update(exit=proc.returncode, stdout=first+out, stderr=err)
		assert proc.returncode == 0, receipt
		rows = [json.loads(line) for line in receipt['stdout'].splitlines()]
		metrics = [r for r in rows if 'cpu_peak' in r]; assert len(metrics) == 1
		m = metrics[0]; assert m['analyses'] == 3 and m['reads'] == 6 and m['responses'] == 12 and m['refusals'] == 3
		assert m['tickets'] == m['retired_tickets'] == 6 and m['entries'] == m['retired_entries'] == 3
		assert m['cpu_peak'] == 2 or a.allow_serialized_tools and m['cpu_peak'] == 1, m
		providers = [r for r in rows if 'custom_contexts' in r]; assert len(providers) == 1
		pr = providers[0]; assert pr['opened'] == pr['disposed'] == 7
		assert {x['identity'] for x in pr['custom_contexts']} == {11, 12, 13, 40, 41, 61, 62}
		for c in pr['custom_contexts']: assert c['allocations'] == c['releases'] and c['peak'] <= c['capacity'] and c['refusals'] == 0
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
	print('PASS: paired queries, independent distributions, cache reuse and TCP/UDP progress (regression only)')


if __name__ == '__main__': main()
