#!/usr/bin/python3 -I
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Installed development CLI; authenticate private images before native exec."""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import sys


def main():
	root = Path(__file__).resolve().parents[1]/'lib/astra'
	manifest = json.loads((root/'INSTALL.json').read_text())
	doc = len(sys.argv) > 1 and sys.argv[1] == 'doc'
	selected = ['astrac', 'astrac.doc' if doc else 'astrac.native']
	if not doc and 'system_llvm' not in manifest:
		selected += ['llvm/libLLVM.so.23.1']
	for name in selected:
		path = root/name
		pin = manifest['files'][name]
		with path.open('rb') as stream:
			digest = hashlib.file_digest(stream, 'sha256').hexdigest()
		if path.is_symlink() or path.stat().st_size != pin['bytes'] or digest != pin['sha256']:
			raise ValueError('installed input identity mismatch: '+name)
	env = dict(os.environ)
	for key in ('LD_PRELOAD', 'LD_LIBRARY_PATH', 'LIBRARY_PATH'):
		env.pop(key, None)
	if sys.argv[1:] == ['--version'] and 'system_llvm' in manifest:
		llvm = ctypes.CDLL(manifest['system_llvm']['library']['path'])
		llvm.LLVMGetVersion.argtypes = [ctypes.POINTER(ctypes.c_uint)]*3
		fields = [ctypes.c_uint() for unused in range(3)]
		llvm.LLVMGetVersion(*map(ctypes.byref, fields))
		version = '.'.join(str(field.value) for field in fields)
		print('astrac 0.0.3-dev28c1 (GNU/Linux x86-64, E25-A-v1, LLVM '+version+')')
		return
	os.execve(root/'astrac', ['astrac', *sys.argv[1:]], env)


if __name__ == '__main__':
	try:
		main()
	except (OSError, ValueError, KeyError) as error:
		print('astrac: installation unavailable: '+str(error), file=sys.stderr)
		sys.exit(127)
