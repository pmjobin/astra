#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused record-result evaluation, error-edge and physical-consumer checks."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--component', type=Path)
	p.add_argument('--oracle-only', action='store_true')
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	a = p.parse_args(); assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	assert a.oracle_only == (a.component is None)
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('record-values-'+a.version+'-'+a.mode); build = a.build_root/leaf.name; leaf.mkdir(); build.mkdir()
	recipe = Path(__file__); (leaf/'recipe.py.txt').write_bytes(recipe.read_bytes()); recipe_sha256 = sha(recipe)
	component_sha256 = None; objects = []
	if a.component:
		identity = json.loads(a.component.with_suffix('.identity.json').read_text())
		assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
		for group in ('sources', 'tools'):
			assert all(sha(name) == expected for name, expected in identity['identity'][group].items()), group
		component_sha256 = sha(a.component)
		objects = [a.component.parent/(name+'.o') for name in ('args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap')]
		assert all(path.is_file() for path in objects)
	commands = []; rows = []; env = dict(os.environ, CCACHE_DISABLE='1')
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
	def memory(exe, name):
		run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name, 42)
		assert all(token in (leaf/(name+'.stderr')).read_bytes() for token in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	fixture = recipe.with_suffix('.astra').read_text()
	for label, text in [('original', fixture), ('renamed', fixture.replace('ValuePair', 'ResultFields').replace('ValueCounter', 'ReadCounter').replace('left', 'first').replace('right', 'second'))]:
		source = leaf/(label+'.astra'); source.write_text(text); inputs = [source, ROOT/'lib/astra/base/errors.astra']
		links = [word for obj in objects for word in ('--link-object', obj)]
		oracle = build/(label+'-C0'); run([a.compiler, '-'+a.mode, *inputs, *links, '-o', oracle], label+'-C0-build'); run([oracle], label+'-C0-execute', 42); memory(oracle, label+'-C0-memory')
		row = dict(name=label, sources={str(path):sha(path) for path in inputs}, C0_ELF_sha256=sha(oracle), C0_exit=42, C0_unsuppressed_memory=True, Astra_native_execution=None)
		if a.component:
			physical = build/(label+'.ll'); physical.write_bytes(b'Record projection output sentinel\n')
			run([a.component, '--shared-stages', *inputs], label+'-stages', 42)
			run([a.component, '--record-value-controls', *inputs], label+'-controls', 42)
			run([a.component, '--native', physical, *inputs], label+'-native')
			run(['opt', '-passes=verify', '-disable-output', physical], label+'-verify')
			optimized = build/(label+'-optimized.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', physical, '-o', optimized], label+'-optimize'); run(['opt', '-passes=verify', '-disable-output', optimized], label+'-optimized-verify')
			obj = build/(label+'.o'); run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], label+'-object')
			exe = build/(label+'-Astra'); run(['cc', '-no-pie', obj, *objects, '-o', exe], label+'-link'); run([exe], label+'-execute', 42); memory(exe, label+'-memory')
			run(['readelf', '-h', exe], label+'-ELF'); header = (leaf/(label+'-ELF.stdout')).read_text(); assert 'ELF64' in header and 'Advanced Micro Devices X86-64' in header
			for stream in ('stdout', 'stderr'): assert (leaf/(label+'-execute.'+stream)).read_bytes() == (leaf/(label+'-C0-execute.'+stream)).read_bytes()
			row.update(Astra_native_execution=42, Astra_unsuppressed_memory=True, raw_LLVM_sha256=sha(physical), optimized_LLVM_sha256=sha(optimized), object_sha256=sha(obj), Astra_ELF_sha256=sha(exe))
		rows.append(row); assert sha(recipe) == recipe_sha256
		write(leaf/'result.json', dict(status='ORIGINAL_C0_ORACLES_ONLY' if a.oracle_only else 'FOCUSED_RECORD_RESULT_NATIVE_PASS', mode=a.mode, component_sha256=component_sha256, compiler_sha256=sha(a.compiler), LLVM_library_sha256=sha('/usr/lib64/libLLVM.so.23.1'), recipe_sha256=recipe_sha256, programs=rows, full_original_compiler_credit=0, limitation='Flat copyable record results only. Nested records and record memory admission remain separate. The source/model perturbations and LLVM-valid wrong-aggregate replacements are restored before native emission; refused alternatives are never executed. No inherited 340/71 regression or Stage1 credit.'))
		print(label, 'C0=42', 'Astra=42' if a.component else 'oracle only', flush=True)


if __name__ == '__main__':
	main()
