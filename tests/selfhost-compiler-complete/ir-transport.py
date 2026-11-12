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
	p.add_argument('--astra-only', action='store_true', help='Focused real Astra import test; reuse the separately qualified C transport campaign.')
	p.add_argument('--capsule-prefix', type=Path)
	p.add_argument('--inside-capsule', action='store_true', help=argparse.SUPPRESS)
	a = p.parse_args(); assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	if a.capsule_prefix and not a.inside_capsule:
		assert a.capsule_prefix.resolve().is_relative_to((WORK/'runtime').resolve())
		raise SystemExit(subprocess.call([*json.loads(a.capsule_prefix.read_text()), '--', sys.executable, '-B', str(Path(__file__).resolve()), '--inside-capsule', *sys.argv[1:]]))
	leaf = output_path(a.runtime_root/('ir-transport-'+a.version), WORK/'runtime'); leaf.mkdir()
	build = output_path(a.build_root/leaf.name, WORK/'build'); build.mkdir()
	sources = [ROOT/'compiler/backend/llvm/capi.c', Path(__file__).with_suffix('.c')]
	astra_sources = [ROOT/'compiler/backend/llvm/capi.astra', Path(__file__).with_suffix('.astra')]
	digests = {str(path):sha(path) for path in [*sources, *astra_sources]}
	for path in [*sources, *astra_sources]: (leaf/path.name).write_bytes(path.read_bytes())
	commands = []
	def run(name, argv, expected=0):
		result = execute(argv, leaf/name, expected=expected, timeout=180, env=dict(os.environ, CCACHE_DISABLE='1'))
		commands.append(dict(name=name, **result)); write(leaf/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result['exit'], (leaf/name/'stderr').read_text()[-2000:])
		print(name, round(result['seconds'], 3), flush=True)
		return (leaf/name/'stdout').read_bytes()
	run('toolchain', [sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/toolchain.py', '--compiler', a.compiler, '--receipt', leaf/'toolchain.json'])
	flags = shlex.split(subprocess.check_output(['llvm-config', '--cflags', '--ldflags', '--libs', 'core', 'target', 'native'], text=True))
	adapter = build/'capi.o'; args = build/'args.o'
	run('adapter-build', ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', sources[0], *flags, '-o', adapter])
	run('args-build', ['cc', '-std=c11', '-O2', '-c', ROOT/'lib/runtime/platform/args-posix.c', '-o', args])
	library = subprocess.check_output(['llvm-config', '--link-shared', '--libs', 'core', 'target', 'native'], text=True).strip()
	assert library.startswith('-l') and ' ' not in library
	imports = []
	for mode in ('O0', 'O2'):
		exe = build/('astra-transport-'+mode)
		run(mode+'-Astra-build', [a.compiler, '-'+mode, *astra_sources, '--link-object', adapter, '--link-object', args, '--link-library', library[2:], '-o', exe])
		for memory in (False, True):
			output = build/(mode+('-Astra-memory' if memory else '-Astra-native')); output.mkdir()
			path = output/'éπ界-output.ll'; sentinel = output/'éπ界-sentinel.ll'; sentinel.write_bytes(b'UNCHANGED\n')
			argv = [exe, path, sentinel]
			if memory: argv = ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv]
			name = mode+'-Astra-'+('memory' if memory else 'execute')
			assert run(name, argv, 42) == b''
			assert sentinel.read_bytes() == b'UNCHANGED\n'
			assert set(p.name for p in output.iterdir()) == {path.name, sentinel.name}
			assert path.read_bytes() == b'\ndeclare i32 @transport()\n'
			run(name+'-verify', ['opt', '-passes=verify', '-disable-output', path])
			if memory: assert all(marker in (leaf/name/'stderr').read_bytes() for marker in [b'in use at exit: 0 bytes in 0 blocks', b'ERROR SUMMARY: 0 errors', b'(suppressed: 0 from 0)'])
		imports.append(dict(profile=mode, executable_sha256=sha(exe), actual_declaration_sha256=sha(astra_sources[0]), actual_adapter_sha256=sha(sources[0]), UTF8_path_bytes=len(str(path).encode()), actual_returns=[1, 1, 1, 2, 1, 0], strict_memory=True))
	if a.astra_only:
		assert all(sha(path) == digest for path, digest in digests.items())
		write(leaf/'result.json', dict(status='ACTUAL_ASTRA_IR_IMPORT_PASSED', sources=digests, products=imports, full_original_native_credit=0, limitation='Actual production declaration and C adapter, exact UTF8 path bytes, refusal returns and sentinels under C0 O0/O2. Transport boundary only; no whole-module compiler qualification.'))
		print('ACTUAL_ASTRA_IR_IMPORT_PASSED', leaf, flush=True)
		return
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
	write(leaf/'result.json', dict(status='BOUNDED_IR_TRANSPORT_PASSED', sources=digests, products=products, actual_Astra_imports=imports, legacy_max_bytes=16777216, compiler_IR_max_bytes=134217728, original_CFG_blocks=375907, proven_label_prefix_lower_bound=375907*50, full_original_native_credit=0, limitation='Mechanical LLVM C adapter and atomic bounded output only. Synthetic valid IR exercises transport past16MiB, preserving the legacy cap, invalid-module rejection and refusal sentinels. Small real ELF/C ABI clients return42 at both profiles. No full compiler source admission, original module completion, 256-generic/8M-SSA change or Stage1 credit.'))
	print('BOUNDED_IR_TRANSPORT_PASSED', leaf, flush=True)


if __name__ == '__main__':
	main()
