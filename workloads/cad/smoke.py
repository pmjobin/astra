#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Run the original constant-image CAD case with a standard-library PNG writer."""
import argparse
import binascii
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import zlib


def chunk(kind, data):
	return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', binascii.crc32(kind + data))


def run(program, output):
	output.mkdir(parents=True, exist_ok=False)
	# Exact pixels from f415381 tests/test_cad.py Synthetic.test_01_constants.
	data = (b'\0' + bytes([37, 119, 213]) * 16) * 12
	png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 16, 12, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(data)) + chunk(b'IEND', b'')
	(output / 'input.png').write_bytes(png)
	command = [str(program), 'input.png', 'output.png', '4', '3']
	p = subprocess.run(command, cwd=output, capture_output=True, env=dict(os.environ, LD_LIBRARY_PATH=str(program.parent)))
	(output / 'stdout').write_bytes(p.stdout)
	(output / 'stderr').write_bytes(p.stderr)
	result = {'argv': command, 'cwd': str(output), 'status': p.returncode, 'input_sha256': hashlib.sha256(png).hexdigest()}
	if p.returncode == 0:
		result['output_sha256'] = hashlib.sha256((output / 'output.png').read_bytes()).hexdigest()
		result['summary'] = json.loads(p.stdout)
	(output / 'result.json').write_text(json.dumps(result, indent='\t') + '\n')
	if p.returncode:
		raise RuntimeError(f'CAD smoke failed; inspect {output}')
		# Existing CAD-1/CAD-2 control, not a newly generated expectation.
	if result['output_sha256'] != '749b331e85b16a049f15dab5d85b1ec3590cbde32f9cf608a520034110338083' or result['summary'] != {'iterations': 15, 'converged': True}:
		raise RuntimeError(f'original CAD control differs; inspect {output}')
	return result


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--program', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	args = parser.parse_args()
	print(json.dumps(run(args.program.resolve(), args.output.resolve()), indent='\t'))
