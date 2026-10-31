#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Probe only M17's explicitly approved temporary private peer topology.

This qualifies host facilities, not the Astra network implementation. Run with
--receipt under the project's runtime area. No host interface/route is changed.
"""
import argparse
import contextlib
import hashlib
import json
import os
from pathlib import Path
import select
import signal
import socket
import subprocess
import sys
import time


HERE = Path(__file__).resolve()
ADDRESSES = ((socket.AF_INET, "192.0.2.1", "192.0.2.2"),
	(socket.AF_INET6, "fd17:6173:7472::1", "fd17:6173:7472::2"))
PAYLOAD = bytes((i * 37 + i // 251) % 256 for i in range(8193))


def netns():
	return os.readlink("/proc/self/ns/net")


def emit(value):
	print(json.dumps(value), flush=True)


def line(process, seconds=12):
	if not select.select([process.stdout], [], [], seconds)[0]:
		raise TimeoutError("peer control deadline")
	value = process.stdout.readline()
	if not value:
		raise RuntimeError("peer exited before its control message")
	return json.loads(value)


def receive(connection, count):
	result = bytearray()
	while len(result) < count:
		part = connection.recv(min(997, count - len(result)))
		if not part:
			raise RuntimeError("unexpected TCP EOF")
		result.extend(part)
	return bytes(result)


def peer(client_mode=False):
	expected_payload = bytes((i * 19 + i // 37) % 256 for i in range(8193)) if client_mode else PAYLOAD
	emit({"namespace": netns(), "pid": os.getpid()})
	if sys.stdin.readline().strip() != "start":
		raise RuntimeError("missing topology start")
	with contextlib.ExitStack() as stack:
		listeners = []
		for family, _, address in ADDRESSES:
			for kind in (socket.SOCK_STREAM, socket.SOCK_DGRAM):
				listener = stack.enter_context(socket.socket(family, kind))
				listener.settimeout(10)
				listener.bind((address, 0))
				if kind == socket.SOCK_STREAM:
					listener.listen(1)
				listeners.append((listener, kind))
		emit({"listeners": [s.getsockname() for s, _ in listeners]})
		observations = []
		for listener, kind in listeners:
			if kind == socket.SOCK_STREAM:
				connection, remote = listener.accept()
				with connection:
					connection.settimeout(10)
					data = receive(connection, len(expected_payload))
					if data != expected_payload:
						raise RuntimeError("TCP peer payload mismatch")
					connection.sendall(data)
					connection.shutdown(socket.SHUT_WR)
					if connection.recv(1) != b"":
						raise RuntimeError("missing client half-close")
				observations.append({"protocol": "tcp", "peer": remote,
					"local": listener.getsockname(), "bytes": len(data),
					"sha256": hashlib.sha256(data).hexdigest()})
			else:
				packets = (b"", expected_payload[:4097], expected_payload[:4097]) if client_mode else (b"", expected_payload[:4097])
				for expected in packets:
					data, remote = listener.recvfrom(65535)
					if data != expected:
						raise RuntimeError("UDP peer payload mismatch")
					listener.sendto(data, remote)
					observations.append({"protocol": "udp", "peer": remote,
						"local": listener.getsockname(), "bytes": len(data),
						"sha256": hashlib.sha256(data).hexdigest()})
		emit({"status": "PASS", "observations": observations})


def command(*args):
	return subprocess.run(args, text=True, capture_output=True,
		check=True, timeout=5).stdout


def inside(host_namespace, client=None):
	if netns() == host_namespace or os.geteuid() != 0:
		raise RuntimeError("refusing configuration outside fresh user/network namespace")
	links = json.loads(command("ip", "-j", "link", "show"))
	if [link["ifname"] for link in links] != ["lo"]:
		raise RuntimeError("refusing nonempty network namespace")
	child = subprocess.Popen(["unshare", "--net", sys.executable, str(HERE),
		"--peer", *(["--client-mode"] if client else [])], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
	try:
		identity = line(child)
		if identity["namespace"] in (host_namespace, netns()) or identity["pid"] != child.pid:
			raise RuntimeError("peer namespace identity mismatch")
		command("ip", "link", "add", "m17a", "type", "veth", "peer", "name", "m17b")
		command("ip", "link", "set", "m17b", "netns", str(child.pid))
		peer_command = ("nsenter", f"--net=/proc/{child.pid}/ns/net", "--")
		for prefix, interface, ipv4, ipv6 in (
			((), "m17a", "192.0.2.1/30", "fd17:6173:7472::1/64"),
			(peer_command, "m17b", "192.0.2.2/30", "fd17:6173:7472::2/64")):
			command(*prefix, "ip", "link", "set", "lo", "up")
			command(*prefix, "ip", "addr", "add", ipv4, "dev", interface)
			command(*prefix, "ip", "-6", "addr", "add", ipv6, "dev", interface, "nodad")
			command(*prefix, "ip", "link", "set", interface, "up")
		interfaces = {"local": json.loads(command("ip", "-j", "addr", "show")),
			"peer": json.loads(command(*peer_command, "ip", "-j", "addr", "show"))}
		child.stdin.write("start\n")
		child.stdin.flush()
		listeners = line(child)["listeners"]
		observations = []
		for index, destination in enumerate(listeners):
			if client:
				if index % 2:
					continue
				invocation = [str(client), destination[0], str(4 if index == 0 else 6)]
				run = subprocess.run(invocation, capture_output=True, text=True, timeout=12,
					env=dict(os.environ, M17_TCP_PORT=str(destination[1]), M17_UDP_PORT=str(listeners[index + 1][1])))
				observations.append({"command": invocation, "exit": run.returncode,
					"stdout": run.stdout, "stderr": run.stderr})
				if run.returncode:
					raise RuntimeError(observations[-1])
				continue
			family, address, _ = ADDRESSES[index // 2]
			kind = socket.SOCK_STREAM if index % 2 == 0 else socket.SOCK_DGRAM
			with socket.socket(family, kind) as client:
				client.settimeout(10)
				client.bind((address, 0))
				if kind == socket.SOCK_STREAM:
					client.connect(tuple(destination))
					for start in range(0, len(PAYLOAD), 127):
						client.sendall(PAYLOAD[start:start + 127])
					client.shutdown(socket.SHUT_WR)
					if receive(client, len(PAYLOAD)) != PAYLOAD or client.recv(1) != b"":
						raise RuntimeError("TCP reply/EOF mismatch")
				else:
					for payload in (b"", PAYLOAD[:4097]):
						client.sendto(payload, tuple(destination))
						data, remote = client.recvfrom(65535)
						if data != payload or list(remote) != destination:
							raise RuntimeError("UDP reply/address mismatch")
				observations.append({"local": client.getsockname(), "peer": destination})
		result = line(child)
		if child.wait(timeout=5) != 0 or result["status"] != "PASS":
			raise RuntimeError("peer did not join successfully")
		emit({"status": "PASS", "scope": "Astra client against independent separate namespace peer" if client else "host topology probe; no Astra product executed",
			"namespace": netns(), "peer_identity": identity, "interfaces": interfaces,
			"client_observations": observations, "peer_result": result,
			"joined": True, "transferred_bytes": 4 * (8193 + 4097 * (2 if client else 1))})
	finally:
		if child.poll() is None:
			child.terminate()
			try:
				child.wait(timeout=3)
			except subprocess.TimeoutExpired:
				child.kill()
				child.wait(timeout=3)
		child.stdin.close()
		child.stdout.close()
		# Only task-owned interfaces inside the verified fresh namespace.
		subprocess.run(["ip", "link", "del", "m17a"], capture_output=True, timeout=3)


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("--receipt", type=Path)
	parser.add_argument("--inside")
	parser.add_argument("--peer", action="store_true")
	parser.add_argument("--client-mode", action="store_true")
	parser.add_argument("--client", type=Path)
	parser.add_argument("--compiler", type=Path)
	args = parser.parse_args()
	if args.peer:
		peer(args.client_mode)
	elif args.inside:
		inside(args.inside, args.client)
	else:
		if not args.receipt:
			parser.error("--receipt is required")
		started = time.monotonic()
		invocation = ["unshare", "--user", "--map-root-user", "--net", "--",
			sys.executable, str(HERE), "--inside", netns()]
		identities = {}
		if args.client:
			if not args.compiler:
				parser.error("--client requires --compiler for source-bound receipts")
			invocation += ["--client", str(args.client.resolve(strict=True))]
			root = HERE.parents[2]
			for source in [args.client, args.compiler, root / 'tests/runtime-composition-17/endpoint-client.astra',
				root / 'tests/runtime-composition-17/endpoint-config.c', root / 'lib/astra/hosted/network.astra',
				root / 'lib/runtime/platform/network-posix.c', root / 'lib/runtime/platform/network-posix.h']:
				identities[str(source.resolve())] = hashlib.sha256(source.read_bytes()).hexdigest()
		process = subprocess.Popen(invocation, stdout=subprocess.PIPE,
			stderr=subprocess.PIPE, text=True, start_new_session=True)
		try:
			out, err = process.communicate(timeout=55)
		except subprocess.TimeoutExpired:
			os.killpg(process.pid, signal.SIGKILL)
			out, err = process.communicate(timeout=3)
		result = {"command": invocation, "exit": process.returncode, "stdout": out,
			"stderr": err, "seconds": time.monotonic() - started,
			"script_sha256": hashlib.sha256(HERE.read_bytes()).hexdigest(), "identities": identities}
		result['identities_unchanged'] = all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest for path, digest in identities.items())
		args.receipt.write_text(json.dumps(result, indent=2) + "\n")
		emit(result)
		return 0 if process.returncode == 0 and result['identities_unchanged'] and json.loads(out)["status"] == "PASS" else 1
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
