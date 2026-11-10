#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused production slot-runtime IR/ABI/memory checks without a full host build."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, declarations, sha, write

ORACLE = '''extern(C) void observed(int code);
class Item {
	int code;
	init(int code) { this.code = code; }
	deinit() { observed(this.code); }
}
int main() {
	{
		var values = new Bag<Item>();
		if (values.reserve(-1) || !values.reserve(2)) return 3;
		var a = new Item(20); var b = new Item(22);
		values.append(move a); values.append(move b);
		if (!values.reserve(5)) return 4;
		var taken = values.take(0);
		if (taken.code != 20 || values.count() != 1 || values.capacity() != 5) return 5;
		var replacement = new Item(24); values.replace(0, move replacement);
		values.append(move taken);
	}
	return 42;
}
'''


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--provider-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	a = p.parse_args()
	assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('slot-runtime-'+a.version)
	build = a.build_root/leaf.name
	leaf.mkdir()
	build.mkdir()
	recipe_paths = [Path(__file__), Path(__file__).with_name('slot-runtime-driver.astra'), Path(__file__).with_name('slot-runtime-observer.c'), ROOT/'compiler/backend/llvm/capi.astra', ROOT/'lib/astra/collections/bag.astra']
	recipe_inputs = []
	for number, path in enumerate(recipe_paths):
		witness = leaf/('input-'+str(number)+'.txt')
		witness.write_bytes(path.read_bytes())
		recipe_inputs.append(dict(path=str(path), sha256=sha(path), witness=str(witness)))
	source = ROOT/'compiler/backend/llvm/recover-buffer.astra'
	raw = source.read_bytes()
	first = raw.index(b'class RecoverSlotWriter {')
	view = leaf/'actual-slot-writer.astra'
	view.write_bytes(raw[first:])
	consumer_source = ROOT/'compiler/backend/llvm/class-storage-slots-check.astra'
	consumer_raw = consumer_source.read_bytes()
	consumer_first = consumer_raw.index(b'class LlvmStorageCursor {')
	consumer_end = consumer_raw.index(b'bool llvm_storage_slot_verified(')
	body_first = consumer_raw.index(b'bool llvm_storage_slot_body_verified(')
	body_end = consumer_raw.index(b'bool llvm_storage_slots_verify(')
	consumer_view = leaf/'actual-slot-consumer.astra'
	consumer_view.write_bytes(consumer_raw[consumer_first:consumer_end]+consumer_raw[body_first:body_end])
	support_sources = [(ROOT/'compiler/backend/llvm/check.astra', b'bool llvm_check_attributes('), (ROOT/'compiler/backend/llvm/class-storage-check.astra', b'bool llvm_storage_free_verified(')]
	support_view = leaf/'actual-consumer-support.astra'
	support_view.write_bytes(b'\n'.join(path.read_bytes()[path.read_bytes().index(marker):].split(b'\n}\n', 1)[0]+b'\n}\n' for path, marker in support_sources))
	commands = []
	env = dict(os.environ, CCACHE_DISABLE='1')
	for name in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE'):
		env.pop(name, None)
	def run(argv, name, expected=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		with (leaf/(name+'.stdout')).open('wb') as out, (leaf/(name+'.stderr')).open('wb') as err:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=build, env=env, stdout=out, stderr=err, start_new_session=True)
			timed_out = False
			try:
				code = process.wait(180)
			except subprocess.TimeoutExpired:
				timed_out = True
				os.killpg(process.pid, signal.SIGKILL)
				code = process.wait()
		commands.append(dict(name=name, argv=argv, exit=code, timed_out=timed_out, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		write(leaf/'commands.json', commands)
		assert not timed_out and code in expected, (name, code)
		return code
	run([a.compiler, '--dump-syntax', source], 'production-AST')
	run([a.compiler, '--dump-syntax', view], 'view-AST')
	original = declarations((leaf/'production-AST.stdout').read_text())
	selected = declarations((leaf/'view-AST.stdout').read_text())
	assert len(selected) == 1 and selected[0] in original
	for label, actual, extracted in [('consumer', consumer_source, consumer_view), *[(str(i)+'-support', path, support_view) for i, (path, _) in enumerate(support_sources)]]:
		run([a.compiler, '--dump-syntax', actual], label+'-production-AST')
		run([a.compiler, '--dump-syntax', extracted], label+'-view-AST')
		actual_declarations = declarations((leaf/(label+'-production-AST.stdout')).read_text())
		extracted_declarations = declarations((leaf/(label+'-view-AST.stdout')).read_text())
		if label == 'consumer':
			assert len(extracted_declarations) == 2 and all(row in actual_declarations for row in extracted_declarations)
		else:
			assert len(extracted_declarations) == 2 and extracted_declarations[int(label[0])] in actual_declarations
	producer = build/'slot-producer'
	ffi = a.provider_root/'llvm-capi.o'
	args = a.provider_root/'args-posix.o'
	assert ffi.is_file() and args.is_file()
	run([a.compiler, '-O0', view, consumer_view, support_view, ROOT/'compiler/backend/llvm/capi.astra', Path(__file__).with_name('slot-runtime-driver.astra'), '--link-object', ffi, '--link-object', args, '--link-library', 'LLVM-23', '-o', producer], 'producer-build')
	modules = [build/('drop'+str(convention)+'.ll') for convention in (0, 8)]
	run([producer, *modules], 'produce-actual-helpers')
	oracle_source = leaf/'oracle.astra'
	oracle_source.write_text(ORACLE)
	provider = leaf/'oracle-provider.c'
	provider.write_text('#include <stdio.h>\nvoid observed(int code) { printf("%d\\n", code); }\n')
	provider_object = build/'oracle-provider.o'
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', provider_object], 'oracle-provider')
	profiles = {}
	def returning(product, label):
		run([product], label+'-execute', (42,))
		run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], label+'-memory', (42,))
		assert (leaf/(label+'-execute.stdout')).read_bytes() == b'22\n20\n24\n'
		assert not (leaf/(label+'-execute.stderr')).read_bytes()
		assert (leaf/(label+'-memory.stdout')).read_bytes() == (leaf/(label+'-execute.stdout')).read_bytes()
		data = (leaf/(label+'-memory.stderr')).read_bytes()
		assert all(marker in data for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	for mode in ('O0', 'O2'):
		oracle = build/('C0-'+mode)
		run([a.compiler, '-'+mode, oracle_source, ROOT/'lib/astra/collections/bag.astra', '--link-object', provider_object, '-o', oracle], mode+'-C0-build')
		returning(oracle, mode+'-C0')
		rows = []
		for convention, module in zip((0, 8), modules):
			label = mode+'-drop'+str(convention)
			run(['opt', '-passes=verify', '-disable-output', module], label+'-verify')
			optimized = build/(label+'.ll')
			run(['opt', '-passes=default<'+mode+'>', '-S', module, '-o', optimized], label+'-optimize')
			run(['opt', '-passes=verify', '-disable-output', optimized], label+'-optimized-verify')
			obj = build/(label+'.o')
			run(['llc', '-filetype=obj', '-'+mode, optimized, '-o', obj], label+'-object')
			exe = build/label
			run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-no-pie', Path(__file__).with_name('slot-runtime-observer.c'), obj, '-o', exe], label+'-ABI-link')
			returning(exe, label)
			faults = []
			for fault in range(1, 7):
				code = run([exe, str(fault)], label+'-fault'+str(fault), (-4, 132))
				faults.append(dict(case=fault, exit=code, returning_memory_credit=False))
			rows.append(dict(drop_calling_convention=convention, raw_LLVM_sha256=sha(module), optimized_LLVM_sha256=sha(optimized), object_sha256=sha(obj), ELF_sha256=sha(exe), actual_exit=42, C_ABI_descriptor=dict(bytes=16, alignment=8, offsets=[0, 8, 12]), clean_unsuppressed_memory=True, faults=faults))
		profiles[mode] = dict(C0_ELF_sha256=sha(oracle), actual_C0_exit=42, helpers=rows)
	assert source.read_bytes() == raw
	assert consumer_source.read_bytes() == consumer_raw
	assert all(sha(row['path']) == row['sha256'] for row in recipe_inputs)
	write(leaf/'result.json', dict(status='OWNING_CLASS_SLOT_RUNTIME_HELPERS_QUALIFIED', profiles=profiles, recipe_inputs=recipe_inputs, production_source=dict(path=str(source), sha256=sha(source), view_first=first, view_last=len(raw), view_sha256=sha(view), normalized_C0_AST=selected[0]), independent_consumer=dict(path=str(consumer_source), sha256=sha(consumer_source), view_sha256=sha(consumer_view), support=[dict(path=str(path), sha256=sha(path)) for path, _ in support_sources], support_view_sha256=sha(support_view), positive_graphs=10, LLVM_valid_instruction_mutations=24, refused_signature_conventions=20, restored_graphs=10), generator=dict(path=str(producer), sha256=sha(producer), built_by_C0=True), provider_inputs=[dict(path=str(path), sha256=sha(path)) for path in (ffi, args)], limitation='Exact complete production helper class and physical consumer under unchanged C0, then real LLVM/native owning-Class slot helpers at O0/O2, independent GCC C ABI layout/behavior and C0 original Bag lifetime oracle. Nonowning record-element helpers remain unqualified here. Six fatal controls/profile/convention receive no returning-memory credit. This is not an Astra-built compiler, source/Flow/SSA slot admission, an independent whole-module physical consumer or a full original compiler qualification. The new source feature remains gated until those proofs exist.'))
	print('Actual slot runtime: C0/ABI/order/memory and 24 fatal controls passed; full source admission remains unproved', flush=True)


if __name__ == '__main__':
	main()
