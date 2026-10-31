#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run streaming A only in M17's approved fresh private veth topology."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
sys.dont_write_bytecode = True

HERE = Path(__file__).resolve()
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location('m17_peer', HERE.with_name('runtime-composition-17-peer.py'))
topology = importlib.util.module_from_spec(spec); spec.loader.exec_module(topology)


def inside(host_namespace, product, output):
	if topology.netns() == host_namespace or os.geteuid() != 0:
		raise RuntimeError('refusing configuration outside fresh user/network namespace')
	links = json.loads(topology.command('ip', '-j', 'link', 'show'))
	assert [link['ifname'] for link in links] == ['lo']
	child = subprocess.Popen(['unshare', '--net', sys.executable, str(HERE), '--peer'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
	try:
		identity = topology.line(child)
		assert identity['namespace'] not in (host_namespace, topology.netns()) and identity['pid'] == child.pid
		topology.command('ip', 'link', 'add', 'm17a', 'type', 'veth', 'peer', 'name', 'm17b')
		topology.command('ip', 'link', 'set', 'm17b', 'netns', str(child.pid))
		peer_command = ['nsenter', f'--net=/proc/{child.pid}/ns/net', '--']
		for prefix, interface, ipv4, ipv6 in [((), 'm17a', '192.0.2.1/30', 'fd17:6173:7472::1/64'), (peer_command, 'm17b', '192.0.2.2/30', 'fd17:6173:7472::2/64')]:
			topology.command(*prefix, 'ip', 'link', 'set', 'lo', 'up')
			topology.command(*prefix, 'ip', 'addr', 'add', ipv4, 'dev', interface)
			topology.command(*prefix, 'ip', '-6', 'addr', 'add', ipv6, 'dev', interface, 'nodad')
			topology.command(*prefix, 'ip', 'link', 'set', interface, 'up')
		interfaces = dict(local=json.loads(topology.command('ip', '-j', 'addr', 'show')), peer=json.loads(topology.command(*peer_command, 'ip', '-j', 'addr', 'show')))
		observations = []
		for family, (_, address, remote) in zip(['4', '6'], topology.ADDRESSES):
			data, receipt = output / (family + '.bin'), output / (family + '-peer.json')
			invocation = [str(product), address, family, str(data)]
			server = subprocess.Popen(invocation, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
			try:
				ready = topology.line(server); assert ready['pid'] == server.pid
				client = [*peer_command, sys.executable, str(ROOT / 'tests/runtime-composition-17/stream-remote-peer.py'), '--address', address, '--bind', remote, '--family', family, '--tcp', str(ready['tcp']), '--udp', str(ready['udp']), '--output', str(data), '--receipt', str(receipt)]
				run = subprocess.run(client, capture_output=True, text=True, timeout=50)
				out, err = server.communicate(timeout=20)
				observation = dict(command=invocation, ready=ready, server_exit=server.returncode, stdout=out, stderr=err, peer_command=client, peer_exit=run.returncode, peer_stdout=run.stdout, peer_stderr=run.stderr)
				observations.append(observation)
				assert server.returncode == 0 and run.returncode == 0, observation
				peer = json.loads(receipt.read_text()); assert peer['namespace'] == identity['namespace'] and peer['tcp_local'][0] == remote and peer['tcp_peer'][0] == address
				metrics = [json.loads(line) for line in out.splitlines() if 'cpu_peak' in line]
				assert len(metrics) == 1 and metrics[0]['cpu_peak'] == 2 and metrics[0]['network_overlap'] > 0 and metrics[0]['io_overlap'] > 0
			finally:
				if server.poll() is None:
					server.terminate()
					try: server.communicate(timeout=5)
					except subprocess.TimeoutExpired: server.kill(); server.communicate(timeout=3)
		child.stdin.write('done\n'); child.stdin.flush(); assert child.wait(timeout=5) == 0
		topology.emit(dict(status='PASS', scope='isolated separate namespace streaming A, IPv4/IPv6 TCP and UDP', namespace=topology.netns(), peer_identity=identity, interfaces=interfaces, observations=observations, joined=True))
	finally:
		if child.poll() is None:
			child.terminate()
			try: child.wait(timeout=3)
			except subprocess.TimeoutExpired: child.kill(); child.wait(timeout=3)
		child.stdin.close(); child.stdout.close()
		subprocess.run(['ip', 'link', 'del', 'm17a'], capture_output=True, timeout=3)


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--peer', action='store_true')
	parser.add_argument('--inside')
	parser.add_argument('--product', type=Path)
	parser.add_argument('--compiler', type=Path)
	parser.add_argument('--output', type=Path)
	parser.add_argument('--receipt', type=Path)
	args = parser.parse_args()
	if args.peer:
		topology.emit(dict(namespace=topology.netns(), pid=os.getpid())); assert sys.stdin.readline().strip() == 'done'; return 0
	if args.inside:
		inside(args.inside, args.product, args.output); return 0
	if any(value is None for value in [args.product, args.compiler, args.output, args.receipt]): parser.error('--product, --compiler, --output and --receipt required')
	args.output.mkdir(parents=True, exist_ok=True)
	files = [args.product.resolve(strict=True), args.compiler.resolve(strict=True), HERE, HERE.with_name('runtime-composition-17-peer.py'), ROOT / 'tests/runtime-composition-17/stream-remote-peer.py', ROOT / 'tests/runtime-composition-17/stream-peer.py', ROOT / 'tests/runtime-composition-17/stream-protocol-oracle.c']
	files += [p for directory in ['examples/runtime-composition-17', 'lib/astra/async', 'lib/astra/memory', 'lib/runtime/runtime', 'lib/astra/platform'] for p in (ROOT / directory).iterdir() if p.is_file()]
	identities = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in files}
	invocation = ['unshare', '--user', '--map-root-user', '--net', '--', sys.executable, str(HERE), '--inside', topology.netns(), '--product', str(args.product.resolve()), '--output', str(args.output.resolve())]
	began = time.monotonic(); process = subprocess.Popen(invocation, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
	try: out, err = process.communicate(timeout=120)
	except subprocess.TimeoutExpired:
		os.killpg(process.pid, signal.SIGKILL); out, err = process.communicate(timeout=3)
	result = dict(command=invocation, exit=process.returncode, stdout=out, stderr=err, seconds=time.monotonic() - began, identities=identities, identities_unchanged=all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == value for path, value in identities.items()))
	args.receipt.write_text(json.dumps(result, indent=2) + '\n'); topology.emit(result)
	return 0 if process.returncode == 0 and result['identities_unchanged'] and json.loads(out)['status'] == 'PASS' else 1


if __name__ == '__main__':
	raise SystemExit(main())
