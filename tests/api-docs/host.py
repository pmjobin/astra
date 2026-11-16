#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent SHA256 and filesystem adversaries for the private doc transport."""
import argparse
import ctypes
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	a.build.mkdir(parents=True, exist_ok=False)
	a.runtime.mkdir(parents=True, exist_ok=False)
	obj = a.build/'doc-host.so'
	subprocess.run(['cc', '-std=c11', '-shared', '-fPIC', '-O2', '-Wall', '-Wextra', '-Werror', ROOT/'compiler/docs/host.c', '-o', obj], check=True)
	lib = ctypes.CDLL(str(obj))
	lib.astrac_doc_sha256.argtypes = [ctypes.c_void_p, ctypes.c_int32, ctypes.c_void_p, ctypes.c_int32]
	lib.astrac_doc_publish.argtypes = [ctypes.c_void_p, ctypes.c_int32, ctypes.c_void_p, ctypes.c_int32]
	for count in (0, 1, 3, 55, 56, 63, 64, 65, 119, 120, 127, 128, 1000000):
		data = bytes((i*31+7) % 256 for i in range(count))
		out = ctypes.create_string_buffer(32)
		assert lib.astrac_doc_sha256(data, count, out, 32) == 0
		assert out.raw == hashlib.sha256(data).digest(), count
	assert lib.astrac_doc_sha256(None, 1, ctypes.create_string_buffer(32), 32) < 0
	assert lib.astrac_doc_sha256(b'', 0, ctypes.create_string_buffer(32), 31) < 0
	data = b'{"format":"astra-api-docs/1","schema_version":1,"symbols":[]}\n'
	def publish(path, payload=data):
		name = str(path).encode()
		return lib.astrac_doc_publish(name, len(name), payload, len(payload))
	path = a.runtime/'api.json'
	assert publish(path) == 0 and path.read_bytes() == data
	assert publish(path, data+b' ') == 0 and path.read_bytes() == data+b' '
	path.write_bytes(b'USER SOURCE BYTES')
	assert publish(path) < 0 and path.read_bytes() == b'USER SOURCE BYTES'
	link = a.runtime/'symlink.json'
	link.symlink_to(path)
	assert publish(link) < 0 and path.read_bytes() == b'USER SOURCE BYTES'
	alias = a.runtime/'alias.json'
	alias.hardlink_to(path)
	assert publish(alias) < 0 and path.read_bytes() == b'USER SOURCE BYTES'
	folder = a.runtime/'directory'
	folder.mkdir()
	through = a.runtime/'linked-directory'
	through.symlink_to(folder, target_is_directory=True)
	assert publish(through/'escape.json') < 0 and not (folder/'escape.json').exists()
	assert publish(a.runtime/'..'/'escape.json') < 0
	assert publish(a.runtime/'nul\0name') < 0
	assert publish(folder) < 0
	result = dict(status='PRIVATE_DOC_TRANSPORT_PASS', sha256_vectors=13, source_sha256=hashlib.sha256((ROOT/'compiler/docs/host.c').read_bytes()).hexdigest(), output_sha256=hashlib.sha256(obj.read_bytes()).hexdigest())
	(a.runtime/'result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(result))


if __name__ == '__main__':
	main()
