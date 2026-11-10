#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact record helper emission/physical-consumer/C-layout/memory checks."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, declarations, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('compiler', 'provider-root', 'build-root', 'runtime-root'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--version', required=True); a = p.parse_args()
	assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('record-runtime-'+a.version); build = a.build_root/leaf.name; leaf.mkdir(); build.mkdir()
	writer_source = ROOT/'compiler/backend/llvm/recover-buffer.astra'; writer = leaf/'actual-writer.astra'; raw_writer = writer_source.read_bytes(); writer.write_bytes(raw_writer[raw_writer.index(b'class RecoverRecordWriter {'):])
	consumer_source = ROOT/'compiler/backend/llvm/recover-storage-abi.astra'; consumer = leaf/'actual-consumer.astra'; raw = consumer_source.read_bytes(); consumer.write_bytes(raw[raw.index(b'int recover_record_memory_leaves('):])
	support = leaf/'actual-support.astra'; bits_source = ROOT/'compiler/backend/llvm/recover-helpers-check.astra'; insert_source = ROOT/'compiler/backend/llvm/recover-carrier-check.astra'
	bits = next(line for line in bits_source.read_bytes().splitlines() if line.startswith(b'bool recover_llvm_bits('))
	insert = insert_source.read_bytes(); insert = insert[insert.index(b'bool recover_llvm_insert('):].split(b'\n}\n', 1)[0]+b'\n}\n'; support.write_bytes(bits+b'\n'+insert)
	recipes = [Path(__file__), Path(__file__).with_name('record-runtime-driver.astra'), Path(__file__).with_name('record-runtime-observer.c'), writer_source, consumer_source, bits_source, insert_source, ROOT/'compiler/backend/llvm/capi.astra', ROOT/'compiler/backend/llvm/recover-shared-capi.astra']
	identities = []
	for i, path in enumerate(recipes):
		witness = leaf/('input-'+str(i)+'.txt'); witness.write_bytes(path.read_bytes()); identities.append(dict(path=str(path), sha256=sha(path), witness=str(witness)))
	commands = []
	def run(argv, name, expected=0):
		argv = list(map(str, argv)); start = time.monotonic()
		process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=build, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True, env=dict(os.environ, CCACHE_DISABLE='1', VALGRIND_OPTS='', LD_PRELOAD=''))
		timed_out = False
		try: out, err = process.communicate(timeout=120)
		except subprocess.TimeoutExpired:
			timed_out = True; os.killpg(process.pid, signal.SIGKILL); out, err = process.communicate()
		p = subprocess.CompletedProcess(argv, process.returncode, out, err)
		(leaf/(name+'.stdout')).write_bytes(p.stdout); (leaf/(name+'.stderr')).write_bytes(p.stderr)
		commands.append(dict(name=name, argv=argv, exit=p.returncode, timed_out=timed_out, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); write(leaf/'commands.json', commands)
		assert not timed_out and p.returncode == expected, (name, p.returncode)
		return p.stdout
	for source, view, name in ((writer_source, writer, 'writer'), (consumer_source, consumer, 'consumer')):
		original = declarations(run([a.compiler, '--dump-syntax', source], name+'-full-syntax').decode()); selected = declarations(run([a.compiler, '--dump-syntax', view], name+'-view-syntax').decode()); assert selected and all(original.count(row) == 1 for row in selected)
	ffi = a.provider_root/'llvm-capi.o'; args = a.provider_root/'args-posix.o'; identity = json.loads((a.provider_root/'astra-native-probe-O0.identity.json').read_text())
	assert sha(ffi) == identity['identity']['sources'][str(ffi)] and sha(args) == identity['identity']['sources'][str(args)]
	producer = build/'generator'; run([a.compiler, '-O0', writer, consumer, support, ROOT/'compiler/backend/llvm/capi.astra', ROOT/'compiler/backend/llvm/recover-shared-capi.astra', Path(__file__).with_name('record-runtime-driver.astra'), '--link-object', ffi, '--link-object', args, '--link-library', 'LLVM-23', '-o', producer], 'producer-build')
	physical = build/'record.ll'; run([producer, physical], 'emit-and-mutate'); run(['opt', '-passes=verify', '-disable-output', physical], 'verify')
	observer = build/'observer.o'; run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', Path(__file__).with_name('record-runtime-observer.c'), '-o', observer], 'observer-build')
	products = []
	for mode in ('O0', 'O2'):
		optimized = build/(mode+'.ll'); run(['opt', '-passes=default<'+mode+'>', '-S', physical, '-o', optimized], mode+'-optimize'); run(['opt', '-passes=verify', '-disable-output', optimized], mode+'-verify')
		obj = build/(mode+'.o'); run(['llc', '-filetype=obj', '-'+mode, optimized, '-o', obj], mode+'-object'); exe = build/('program-'+mode); run(['cc', '-no-pie', obj, observer, '-o', exe], mode+'-link'); run([exe], mode+'-execute', 42)
		run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], mode+'-memory', 42)
		assert all(token in (leaf/(mode+'-memory.stderr')).read_bytes() for token in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		products.append(dict(profile=mode, LLVM_sha256=sha(optimized), object_sha256=sha(obj), ELF_sha256=sha(exe), exit=42, unsuppressed_memory=True))
	assert all(sha(row['path']) == row['sha256'] for row in identities)
	write(leaf/'result.json', dict(status='C0_RECORD_HELPER_KERNEL_PASS', inputs=identities, generator_sha256=sha(producer), raw_LLVM_sha256=sha(physical), memory_bytes=32, carrier_bytes=24, LLVM_valid_restored_mutations=10, products=products, target_native_credit=0, limitation='Exact production helper writer and independent physical traversal under C0, then actual native helper code and independent C layout/padding observer. No Astra source/Flow/Core/SSA record admission, integrated whole-module check or full original compiler completeness is proved.'))
	print('C0_RECORD_HELPER_KERNEL_PASS', flush=True)


if __name__ == '__main__':
	main()
