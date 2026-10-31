#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Capture an existing VM serial console; never configure the guest or hypervisor."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import select
import termios
import time
import tty


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--serial', required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--build-receipt', type=Path, required=True)
	parser.add_argument('--timeout', type=int, default=120)
	parser.add_argument('--profile', choices=['host', 'native', 'com-export', 'com-import', 'applications'], default='host')
	args = parser.parse_args()
	assert 1 <= args.timeout <= 300
	args.output.mkdir(parents=True, exist_ok=True)
	end = b'ASTRA14_NATIVE_END' if args.profile == 'native' else b'ASTRA14_HOST_END'
	if args.profile == 'com-export':
		end = b'ASTRA14_COM_END'
	if args.profile == 'com-import':
		end = b'ASTRA14_IMPORT_END'
	if args.profile == 'applications':
		end = b'ASTRA14_APPS_END'
	raw = args.output / 'windows-serial.txt'
	with raw.open('xb') as sink:
		fd = os.open(args.serial, os.O_RDONLY | os.O_NONBLOCK | os.O_NOCTTY)
		state = termios.tcgetattr(fd)
		data = b''
		try:
			tty.setraw(fd)
			deadline = time.monotonic() + args.timeout
			while time.monotonic() < deadline and len(data) < 200000:
				if select.select([fd], [], [], 1)[0]:
					chunk = os.read(fd, 4096)
					if not chunk:
						break
					data += chunk
					sink.write(chunk)
					sink.flush()
					if end in data:
						break
		finally:
			termios.tcsetattr(fd, termios.TCSANOW, state)
			os.close(fd)
	text = data.decode('utf-8', errors='replace')
	markers = ['ASTRA14_HOST_BEGIN', 'PASS canonical-IUnknown', 'PASS HRESULT-S_OK-S_FALSE-failure',
		'PASS real-STA-and-MTA', 'PASS AddRef-Release counts exactly-one-provider-destruction',
		'HOST_COM_AVAILABLE=YES; compiler-COM-import-export=NOT_TESTED', 'ASTRA14_HOST_EXIT=0', 'ASTRA14_HOST_END']
	build = json.loads(args.build_receipt.read_text())
	scope = 'native Windows independently compiled C++ COM host capability probe only'
	expected_counts = {}
	if args.profile == 'native':
		scope = 'actual Astra Windows word/pointer C ABI and native Shared/Weak; COM adapters NOT_TESTED'
		markers = ['ASTRA14_NATIVE_BEGIN', 'ASTRA_COM_IMPORT_EXPORT=NOT_TESTED', 'ASTRA14_NATIVE_EXIT=0', 'ASTRA14_NATIVE_END']
		for level in ('0', '1', '2'):
			markers += [f'PASS Windows native O{level}: C-word-pointer-roundtrip move explicit-clone weak-upgrade expiry 128-single-destructions',
				f'ASTRA14_NATIVE_O{level}_EXIT=0', build['products'][f'native-O{level}.exe']]
	if args.profile == 'com-export':
		scope = 'actual Astra COM export and mixed C+COM on native Windows; COM import NOT_TESTED'
		markers = ['ASTRA14_COM_BEGIN', 'ASTRA14_COM_EXIT=0', 'ASTRA14_COM_END', build['products']['com-client.exe']]
		for level in ('0', '1', '2'):
			markers += [f'ASTRA14_COM_O{level}_EXIT=0', build['products'][f'com-provider-O{level}.dll']]
		for marker in ['PASS Astra COM two-IIDs', 'PASS Astra COM HRESULT-S_OK-S_FALSE-failure',
			'PASS Astra COM actual-STA-MTA', 'PASS Astra COM exact-native-counts',
			'PASS Astra COM export factory-cache-OOM',
			'ASTRA_COM_EXPORT_WINDOWS_NATIVE=PASS; imported-COM=NOT_TESTED']:
			expected_counts[marker] = 3
			markers.append(marker)
	if args.profile == 'com-import':
		scope = 'actual Astra COM import on native Windows with an independently compiled SDK producer'
		markers = ['ASTRA14_IMPORT_BEGIN', 'ASTRA14_IMPORT_EXIT=0', 'ASTRA14_IMPORT_END', build['products']['import-provider.dll']]
		for level in ('0', '1', '2'):
			markers += [f'ASTRA14_IMPORT_O{level}_EXIT=0', build['products'][f'import-client-O{level}.exe']]
		for marker in ['PASS Astra COM import independent-producer', 'PASS Astra COM import HRESULT-S_FALSE',
			'PASS Astra COM import actual-STA-MTA', 'PASS Astra COM import 128-repeat', 'ASTRA_COM_IMPORT_WINDOWS_NATIVE=PASS']:
			expected_counts[marker] = 3
			markers.append(marker)
	if args.profile == 'applications':
		scope = 'distinct A123 reconciliation, A124 thermostat and A125 C+COM lease budget on native Windows'
		markers = ['ASTRA14_APPS_BEGIN', 'ASTRA14_APPS_EXIT=0', 'ASTRA14_APPS_END', *build['products'].values()]
		for app in ('a123', 'a124', 'a125'):
			for level in ('0', '1', '2'):
				markers.append(f'ASTRA14_{app}_O{level}_EXIT=0')
			marker = 'PASS ' + app.upper() + ':'
			markers.append(marker)
			expected_counts[marker] = 3
	passed = all(marker.lower() in text.lower() for marker in markers) and 'FAIL ' not in text and all(text.count(m) == count for m, count in expected_counts.items())
	result = {'scope': scope,
		'compiler_com_import_export': 'NOT_TESTED', 'status': 'PASS' if passed else 'FAILED_OR_INCOMPLETE',
		'raw_sha256': hashlib.sha256(data).hexdigest(), 'markers': {m: m.lower() in text.lower() for m in markers},
		'occurrences': {m: {'expected': count, 'observed': text.count(m)} for m, count in expected_counts.items()},
		'build_receipt': build}
	if args.profile == 'com-export':
		result['compiler_com_import_export'] = 'EXPORT_AND_MIXED_C_COM_PASS; IMPORT_NOT_TESTED'
	if args.profile == 'com-import':
		result['compiler_com_import_export'] = 'IMPORT_PASS; EXPORT_QUALIFIED_SEPARATELY'
	if args.profile == 'applications':
		result['compiler_com_import_export'] = 'A123_IMPORT_A124_EXPORT_A125_MIXED_EXECUTED'
		result['applications'] = {app: {'status': 'PASS' if passed else 'FAILED_OR_INCOMPLETE',
			'variants': ['O0', 'O1', 'O2'], 'source_sha256': value['source_sha256'],
			'client_sha256': value['client_sha256']} for app, value in build['applications'].items()}
	(args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
	print(text)
	assert passed, 'Windows probe failed or serial receipt incomplete'
	print('PASS: ' + scope)


if __name__ == '__main__':
	main()
