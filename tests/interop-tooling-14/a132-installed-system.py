#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""A132: outside-checkout systems consumer, actual TCP/UDP and owned SIMD data."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import random
import re
import selectors
import shutil
import socket
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
UNITS = ['base/errors.astra', 'collections/bag.astra', 'hosted/network.astra', 'async/threaded.astra',
	'numerics/pcm.astra', 'numerics/vectors.astra']
PROVIDERS = ['async/threaded.c', 'platform/network-posix.c', 'runtime/monitors-13.c', 'runtime/allocation-12.c']
WRAPS = ['astra_net_socket', 'astra_net_accept', 'astra_net_close', 'astra_alloc12_allocate']


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	parser.add_argument('--prefix', type=Path, help='required installed compiler/library prefix for the release gate')
	args = parser.parse_args()
	compiler, output = args.compiler.resolve(), args.output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='a132-', dir=output))
	installed = args.prefix.resolve() if args.prefix else None
	if installed:
		assert compiler == installed / 'bin/astrac'
	lib = installed / 'share/astra' if installed else ROOT / 'lib/astra'
	sources = installed / 'share/astra/examples/interop-tooling-14/a132' if installed else ROOT / 'examples/interop-tooling-14/a132'
	for name in ('main.astra', 'provider.c'):
		shutil.copyfile(sources / name, work / name)
	rows, cases = [], []
	receipt = {'application': 'A132', 'compiler_sha256': sha(compiler), 'checks': rows, 'network_cases': cases,
		'mode': 'installed-prefix' if installed else 'development; final installed release remains required',
		'provider': 'explicit posix-threaded, three workers', 'sources': {str(lib / p): sha(lib / p) for p in UNITS + PROVIDERS}}
	receipt['sources'].update({name: sha(work / name) for name in ('main.astra', 'provider.c')})
	def save():
		(work / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	def run(command, *, expected=0, contains=''):
		assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during qualification'
		p = subprocess.run(list(map(str, command)), cwd=work, capture_output=True, text=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1'))
		rows.append({'command': list(map(str, command)), 'exit': p.returncode, 'expected_exit': expected, 'stdout': p.stdout, 'stderr': p.stderr})
		save()
		assert p.returncode == expected and contains in p.stdout + p.stderr, rows[-1]
		return p.stdout
	receipt['compiler_version'] = run([compiler, '--version']).strip()
	receipt['target'] = run([compiler, '--target-info'], contains='x86_64')
	flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread']
	objects = []
	for i, source in enumerate([work / 'provider.c', *[lib / p for p in PROVIDERS]]):
		obj = work / ('provider-' + str(i) + '.o')
		renames = [name for name in WRAPS if (source.name == 'network-posix.c' and name.startswith('astra_net_')) or (source.name == 'allocation-12.c' and name == 'astra_alloc12_allocate')]
		run(['gcc', *flags, *['-D' + name + '=a132_real_' + name for name in renames], '-I', lib / 'runtime', '-c', source, '-o', obj])
		objects.append(obj)
	units = [work / 'main.astra', *[lib / p for p in UNITS]]
	links = [item for obj in objects for item in ('--link-object', obj)] + ['--link-library', 'pthread']
	# The consumer uses only explicit installed inputs when the prefix is selected.
	if installed:
		assert all(not p.is_relative_to(ROOT) for p in [compiler, *units, *objects])
	rng = random.Random(132)
	fixtures = [([-32000, -1000, 0, 1000, 16000, 30000, 32767, -32768], [-2000, 500, 123, -1500, 20000, 4000, 1, -1])]
	fixtures += [([rng.randint(-32768, 32767) for _ in range(8)], [rng.randint(-32768, 32767) for _ in range(8)]) for _ in range(2)]
	def exchange(binary, level, fixture, failure='', memory=False):
		left, right = fixture
		mixed = [max(-32768, min(32767, a + b)) for a, b in zip(left, right)]
		wanted = struct.pack('<8h', *mixed)
		command = [binary]
		if memory:
			command = ['valgrind', '--vgdb=no', '--default-suppressions=no', '--leak-check=full',
				'--errors-for-leak-kinds=all', '--error-exitcode=99', binary]
		env = dict(os.environ, A132_STATUS='2' if failure else '0', A132_TOTAL='0' if failure else str(sum(mixed)))
		number = len(cases)
		error_path = work / ('network-' + str(number) + '.stderr')
		row = {'command': list(map(str, command)), 'optimization': level, 'left': left, 'right': right, 'failure': failure,
			'expected_pcm_hex': wanted.hex(), 'memory': memory, 'stderr': error_path.name, 'passed': False}
		cases.append(row)
		with error_path.open('w') as errors:
			process = subprocess.Popen(list(map(str, command)), cwd=work, stdout=subprocess.PIPE, stderr=errors, env=env, text=True)
			try:
				with selectors.DefaultSelector() as poll:
					poll.register(process.stdout, selectors.EVENT_READ)
					assert poll.select(20), 'missing server readiness'
				line = process.stdout.readline()
				row['readiness'] = line
				match = re.fullmatch(r'READY A132 (\d+) (\d+)\n', line)
				assert match, line
				tcp_port, udp_port = map(int, match.groups())
				with socket.create_connection(('127.0.0.1', tcp_port), timeout=10) as tcp, socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as udp:
					tcp.settimeout(15); udp.settimeout(15); udp.bind(('127.0.0.1', 0))
					payload = struct.pack('<8h', *left)
					if failure == 'truncated-tcp':
						tcp.sendall(payload[:7]); tcp.shutdown(socket.SHUT_WR)
					else:
						for start in range(0, len(payload), 3):
							tcp.sendall(payload[start:start + 3]); time.sleep(0.002)
						datagram = struct.pack('<8h', *right)
						if failure == 'short-udp':
							datagram = datagram[:5]
						elif failure == 'large-udp':
							datagram += b'\x00'
						udp.sendto(datagram, ('127.0.0.1', udp_port))
					received = b''
					while len(received) < 16:
						part = tcp.recv(16 - len(received))
						if not part:
							break
						received += part
					row['tcp_pcm_hex'] = received.hex()
					if failure:
						assert received == b''
					else:
						assert received == wanted and tcp.recv(1) == b''
						packet, endpoint = udp.recvfrom(64)
						row['udp_pcm_hex'] = packet.hex()
						assert packet == wanted and endpoint == ('127.0.0.1', udp_port)
				stdout, _ = process.communicate(timeout=30)
				row.update(exit=process.returncode, stdout=line + stdout)
				assert process.returncode == 0 and 'PASS A132: provider=posix-threaded' in stdout, row
				row['passed'] = True
			finally:
				if process.poll() is None:
					process.kill(); process.communicate(timeout=10)
				save()
		if memory:
			assert 'ERROR SUMMARY: 0 errors' in error_path.read_text()
	for level in ('0', '1', '2'):
		binary = work / ('systems-O' + level)
		run([compiler, '-O' + level, *units, *links, '-o', binary])
		deps = run(['readelf', '-d', binary])
		assert not any(name in deps for name in ('libgobject', 'libglib', 'libLLVM', 'liburing', 'libstdc++'))
		for fixture in fixtures:
			exchange(binary, level, fixture)
		for failure in ('truncated-tcp', 'short-udp', 'large-udp'):
			exchange(binary, level, fixtures[0], failure)
		if level in ('0', '2'):
			exchange(binary, level, fixtures[0], memory=True)
			exchange(binary, level, fixtures[0], 'truncated-tcp', memory=True)
		receipt.setdefault('variants', []).append({'optimization': level, 'binary_sha256': sha(binary)})
	run([compiler, '--dump-llvm', *units], contains='llvm.sadd.sat.v8i16')
	without_threaded = [item for obj in objects if obj != objects[1] for item in ('--link-object', obj)] + ['--link-library', 'pthread']
	run([compiler, '-O2', *units, *without_threaded, '-o', work / 'missing-provider'], expected=1, contains='astra_async_')
	assert not (work / 'missing-provider').exists()
	receipt['status'] = 'PASS' if installed else 'DEVELOPMENT_PASS; final installed-prefix run required'
	save()
	print(f'{receipt["status"]}: A132 {len(rows)} build/inspection commands and {len(cases)} real independent TCP/UDP/data/lifetime cases; evidence {work}')


if __name__ == '__main__':
	main()
