#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify bounded whole-module IR transport without compiler-admission credit."""
import argparse
import json
import os
from pathlib import Path
import shlex
import struct
import subprocess
import sys

from run import ROOT, WORK, C0_SHA256, sha
from acceleration import execute, output_path, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--capsule-prefix', type=Path)
	p.add_argument('--inside-capsule', action='store_true', help=argparse.SUPPRESS)
	a = p.parse_args(); assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	if a.capsule_prefix and not a.inside_capsule:
		assert a.capsule_prefix.resolve().is_relative_to((WORK/'runtime').resolve())
		raise SystemExit(subprocess.call([*json.loads(a.capsule_prefix.read_text()), '--', sys.executable, '-B', str(Path(__file__).resolve()), '--inside-capsule', *sys.argv[1:]]))
	leaf = output_path(a.runtime_root/('ir-transport-'+a.version), WORK/'runtime'); leaf.mkdir()
	build = output_path(a.build_root/leaf.name, WORK/'build'); build.mkdir()
	sources = [ROOT/'compiler/backend/llvm/capi.c', Path(__file__).with_suffix('.c')]
	digests = {str(path):sha(path) for path in sources}
	for path in sources: (leaf/path.name).write_bytes(path.read_bytes())
	commands = []
	def run(name, argv, expected=0):
		result = execute(argv, leaf/name, expected=expected, timeout=180, env=dict(os.environ, CCACHE_DISABLE='1'))
		commands.append(dict(name=name, **result)); write(leaf/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result['exit'], (leaf/name/'stderr').read_text()[-2000:])
		print(name, round(result['seconds'], 3), flush=True)
		return (leaf/name/'stdout').read_bytes()
	run('toolchain', [sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/toolchain.py', '--compiler', a.compiler, '--receipt', leaf/'toolchain.json'])
	flags = shlex.split(subprocess.check_output(['llvm-config', '--cflags', '--ldflags', '--libs', 'core', 'target', 'native'], text=True))
	client = leaf/'client.c'; client.write_text('extern int f(void); int main(void) { return f(); }\n')
	products = []
	for mode in ('O0', 'O2'):
		profile = build/mode; profile.mkdir(); output = profile/'output'; output.mkdir(); memory = profile/'memory'; memory.mkdir()
		exe = profile/'transport'
		run(mode+'-build', ['cc', '-std=c11', '-'+mode, '-Wall', '-Wextra', '-Werror', '-DTRANSPORT_LEVEL='+mode[1:], *sources, *flags, '-o', exe])
		expected = b'SMALL_IDENTITY LARGE_IR LEGACY_CAP MODULE_CAP INVALID_IR SENTINELS\n'
		assert run(mode+'-execute', [exe, output], 42) == expected
		assert run(mode+'-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe, memory], 42) == expected
		assert all(marker in (leaf/(mode+'-memory')/'stderr').read_bytes() for marker in [b'in use at exit: 0 bytes in 0 blocks', b'ERROR SUMMARY: 0 errors', b'(suppressed: 0 from 0)'])
		assert (output/'legacy.ll').read_bytes() == (output/'module.ll').read_bytes()
		assert (output/'large.ll').stat().st_size > 16777216
		labels = [line for line in (output/'module.ll').read_text().splitlines() if line.startswith('b') and ':' in line]
		assert len(labels) == 3 and all(';' in line and len(line.split(';')[0]) >= 50 for line in labels)
		assert 'No predecessors!' in labels[-1]
		for name in ('legacy.ll', 'module.ll', 'large.ll'): run(mode+'-'+name+'-verify', ['opt', '-passes=verify', '-disable-output', output/name])
		obj = (output/'legacy.o').read_bytes(); assert obj[:6] == b'\x7fELF\x02\x01' and struct.unpack_from('<H', obj, 16)[0] == 1 and struct.unpack_from('<H', obj, 18)[0] == 62
		linked = profile/'client'; run(mode+'-link', ['cc', client, output/'legacy.o', '-o', linked]); run(mode+'-client', [linked], 42)
		for path in output.iterdir(): assert not path.name.startswith(('legacy.ll.', 'module.ll.', 'large.ll.', 'refused.ll.'))
		products.append(dict(profile=mode, executable_sha256=sha(exe), legacy_object_sha256=sha(output/'legacy.o'), linked_client_sha256=sha(linked), large_IR_bytes=(output/'large.ll').stat().st_size, large_IR_sha256=sha(output/'large.ll'), legacy_small_IR_identity=True, clean_strict_memory=True, printed_nonentry_labels=labels))
	assert all(sha(path) == digest for path, digest in digests.items())
	write(leaf/'result.json', dict(status='BOUNDED_IR_TRANSPORT_PASSED', sources=digests, products=products, legacy_max_bytes=16777216, compiler_IR_max_bytes=134217728, original_CFG_blocks=375907, proven_label_prefix_lower_bound=375907*50, full_original_native_credit=0, limitation='Mechanical LLVM C adapter and atomic bounded output only. Synthetic valid IR exercises transport past16MiB, preserving the legacy cap, invalid-module rejection and refusal sentinels. Small real ELF/C ABI clients return42 at both profiles. No full compiler source admission, original module completion, 256-generic/8M-SSA change or Stage1 credit.'))
	print('BOUNDED_IR_TRANSPORT_PASSED', leaf, flush=True)


if __name__ == '__main__':
	main()
