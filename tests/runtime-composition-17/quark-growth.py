#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Isolate the observed GLib 2.88.4 quark-growth allocation; no suppressions."""
from pathlib import Path
import re
import shlex
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import Evidence


def main(compiler, output):
	e = Evidence(compiler, output, 'runtime-composition-17-quark-growth')
	version = e.run(['pkg-config', '--modversion', 'glib-2.0']).stdout.strip()
	assert version == '2.88.4', 'Re-audit this narrow host observation for another GLib version'
	flags = shlex.split(e.run(['pkg-config', '--cflags', '--libs', 'glib-2.0']).stdout)
	libdir = Path(e.run(['pkg-config', '--variable=libdir', 'glib-2.0']).stdout.strip())
	source = Path(__file__).with_name('quark-growth-probe.c')
	product = e.output / 'quark-growth-probe'
	e.files(source, Path(__file__), libdir / 'libglib-2.0.so.0')
	e.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-g', source, *flags, '-o', product])
	tool = ['valgrind', '--default-suppressions=no', '--leak-check=full', '--show-leak-kinds=all',
		'--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=97', product]
	small = e.run([*tool, '8'], contains='ERROR SUMMARY: 0 errors')
	assert re.search(r'definitely lost:\s+0 bytes', small.stderr)
	grown = e.run([*tool, '2048'], expected=97, contains='ERROR SUMMARY: 1 errors')
	assert re.search(r'definitely lost:\s+16,384 bytes in 1 blocks', grown.stderr)
	assert 'g_malloc' in grown.stderr and 'call_init' in grown.stderr
	assert 'quark growth: first=1 inserted=2048 last=2049\n' == grown.stdout
	for kind in ['indirectly', 'possibly']:
		assert re.search(kind + r' lost:\s+0 bytes', grown.stderr)
	e.files(product)
	e.data.update(status='HOST_ALLOCATION_REPRODUCED', glib=version,
		lost_bytes=16384, lost_blocks=1, suppressions=0,
		meaning='Standalone GLib quark-table growth; not an error-free memory-tool result')
	e.save()
	print('OBSERVED: GLib 2.88.4 quark growth: one 16384-byte allocation; no suppressions')


if __name__ == '__main__':
	main(*sys.argv[1:])
