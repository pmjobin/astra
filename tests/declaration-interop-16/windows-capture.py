#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe an authorized existing serial console; never start/control a guest."""
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
	parser.add_argument('--media-receipt', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	args = parser.parse_args()
	args.output.mkdir(parents=True, exist_ok=False)
	media = json.loads(args.media_receipt.read_text())
	data = bytearray()
	with (args.output / 'serial.txt').open('xb') as sink:
		fd = os.open(args.serial, os.O_RDONLY | os.O_NONBLOCK | os.O_NOCTTY)
		state = termios.tcgetattr(fd)
		try:
			tty.setraw(fd)
			deadline = time.monotonic() + 120
			print('Listening on existing serial console', flush=True)
			while time.monotonic() < deadline and len(data) < 200000:
				if select.select([fd], [], [], 1)[0]:
					chunk = os.read(fd, 4096)
					if not chunk:
						break
					data.extend(chunk); sink.write(chunk); sink.flush()
					if b'ASTRA16_BASELINE_END' in data:
						break
		finally:
			termios.tcsetattr(fd, termios.TCSANOW, state)
			os.close(fd)
	text = data.decode('utf8', errors='replace')
	markers = ['ASTRA16_BASELINE_BEGIN', 'ASTRA16_BASELINE_EXIT=0', 'ASTRA16_BASELINE_END',
		*media['products'].values()]
	for direction in ['EXPORT', 'IMPORT']:
		markers += [f'ASTRA16_{direction}_O{level}_EXIT=0' for level in '012']
	missing = [marker for marker in markers if marker.lower() not in text.lower()]
	counts = {marker: text.count(marker) for marker in
		['PASS Astra COM two-IIDs', 'PASS Astra COM import independent-producer']}
	passed = not missing and all(count == 3 for count in counts.values()) and 'FAIL ' not in text
	receipt = dict(scope='native Windows legacy COM continuity only; new declaration-driven ABI NOT_TESTED',
		status='BASELINE_PASS' if passed else 'FAILED_OR_INCOMPLETE',
		serial_sha256=hashlib.sha256(data).hexdigest(),
		media_receipt_sha256=hashlib.sha256(args.media_receipt.read_bytes()).hexdigest(),
		media=media, missing_markers=missing, pass_marker_counts=counts)
	(args.output / 'result.json').write_text(json.dumps(receipt, indent='\t') + '\n')
	print(json.dumps({k: receipt[k] for k in ['status', 'missing_markers', 'pass_marker_counts']}))
	return 0 if passed else 1


if __name__ == '__main__':
	raise SystemExit(main())
