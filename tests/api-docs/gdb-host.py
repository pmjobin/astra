#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Keep host GDB's Python ABI while preserving the pinned inferior environment."""
import os
import sys

env = dict(os.environ)
options = []
for key in ('PATH', 'LD_LIBRARY_PATH', 'LIBRARY_PATH', 'LC_ALL', 'LANG'):
	value = env.get(key)
	if value is not None:
		assert not any(char in value for char in ('\n', '\r', '\0'))
		options += ['-ex', 'set environment '+key+' '+value]
env.pop('LD_LIBRARY_PATH', None)
env.pop('LD_PRELOAD', None)
os.execve('/usr/bin/gdb', ['/usr/bin/gdb', *options, *sys.argv[1:]], env)
