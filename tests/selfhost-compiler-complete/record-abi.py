#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Establish original C0 nested-record value/memory and checked-return ABI."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	a = p.parse_args(); assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('record-abi-'+a.version); build = a.build_root/leaf.name; leaf.mkdir(); build.mkdir()
	fixture = Path(__file__).with_suffix('.astra'); source = leaf/fixture.name; source.write_bytes(fixture.read_bytes()); (leaf/'recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	inputs = [source, ROOT/'lib/astra/base/errors.astra']; commands = []; env = dict(os.environ, CCACHE_DISABLE='1')
	for name in ('LD_PRELOAD', 'VALGRIND_OPTS'): env.pop(name, None)
	def run(argv, name, expected=0):
		argv = list(map(str, argv)); start = time.monotonic()
		with (leaf/(name+'.stdout')).open('wb') as out, (leaf/(name+'.stderr')).open('wb') as err:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=build, env=env, stdout=out, stderr=err, start_new_session=True)
			try: code = process.wait(120)
			except subprocess.TimeoutExpired:
				os.killpg(process.pid, signal.SIGKILL); process.wait(); raise
		commands.append(dict(name=name, argv=argv, exit=code, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); write(leaf/'commands.json', commands)
		assert code == expected, (name, code)
		return (leaf/(name+'.stdout')).read_bytes()
	nabi = run([a.compiler, '--dump-nabi', *inputs], 'native-ABI'); llvm = run([a.compiler, '--dump-llvm', *inputs], 'raw-LLVM')
	raw = build/'C0.ll'; raw.write_bytes(llvm); run(['opt', '-passes=verify', '-disable-output', raw], 'LLVM-verify')
	text = llvm.decode(); checked = next(line for line in text.splitlines() if line.startswith('define internal fastcc ptr @astra.fn.0('))
	parameters = checked.split('(', 1)[1].rsplit(')', 1)[0]; assert [word.strip().split()[0] for word in parameters.split(',')] == ['ptr', 'i8', 'i8', 'i64', 'i8', 'i32']
	read = next(line for line in text.splitlines() if line.startswith('define internal fastcc { i8, i8, i64, i8 } @astra.class.method.'))
	assert '(carrier leaf-aggregate)' in nabi.decode()
	success_slots = []
	for slot in re.findall(r'call fastcc ptr @astra\.fn\.0\(ptr ([^,\s]+),', text):
		allocation = next(line.strip() for line in text.splitlines() if line.strip().startswith(slot+' = alloca '))
		success_slots.append(allocation)
	assert len(success_slots) == 2
	assert '%astra.struct.0 = type { i8, i64 }' in text and '%astra.struct.1 = type { i8, %astra.struct.0, i8 }' in text
	products = []
	for mode in ('O0', 'O2'):
		exe = build/('C0-'+mode); run([a.compiler, '-'+mode, *inputs, '-o', exe], mode+'-build'); run([exe], mode+'-execute', 42)
		header = run(['readelf', '-h', exe], mode+'-ELF').decode(); assert 'ELF64' in header and 'Advanced Micro Devices X86-64' in header
		run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], mode+'-memory', 42)
		assert all(token in (leaf/(mode+'-memory.stderr')).read_bytes() for token in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		products.append(dict(mode=mode, ELF_sha256=sha(exe), exit=42, unsuppressed_memory=True))
	assert source.read_bytes() == fixture.read_bytes()
	write(leaf/'result.json', dict(status='ORIGINAL_C0_RECORD_ABI_BASELINE', compiler_sha256=sha(a.compiler), LLVM_library_sha256=sha('/usr/lib64/libLLVM.so.23.1'), sources=[dict(path=str(path), sha256=sha(path)) for path in inputs], native_ABI_sha256=sha(leaf/'native-ABI.stdout'), raw_LLVM_sha256=sha(raw), checked_signature=checked, method_signature=read, checked_success_slots=success_slots, products=products, target_native_credit=0, limitation='Unmodified original C0 executions establish value/memory layout and normal/error behavior. Astra nested-record admission, native generation, physical mutations and ABI interoperability are not yet proved. No public ABI or approved E25-A-v1 transport is changed.'))
	print('ORIGINAL_C0_RECORD_ABI_BASELINE', flush=True)


if __name__ == '__main__':
	main()
