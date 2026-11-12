#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact production dominators versus independent graph deletion and DFS oracles."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, declarations, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('ssa-dominance-'+a.version); build = a.build_root/leaf.name
	leaf.mkdir(); build.mkdir()
	commands = []; env = dict(os.environ, CCACHE_DISABLE='1')
	for name in ('LD_PRELOAD', 'VALGRIND_OPTS'):
		env.pop(name, None)
	def run(argv, name, expected=0):
		argv = list(map(str, argv)); start = time.monotonic()
		with (leaf/(name+'.stdout')).open('wb') as out, (leaf/(name+'.stderr')).open('wb') as err:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=build, env=env, stdout=out, stderr=err, start_new_session=True)
			try:
				code = process.wait(300)
			except subprocess.TimeoutExpired:
				os.killpg(process.pid, signal.SIGKILL); process.wait(); raise
		commands.append(dict(name=name, argv=argv, exit=code, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		write(leaf/'commands.json', commands)
		assert code == expected, (name, code)
		return (leaf/(name+'.stdout')).read_bytes()
	run(['python3', '-B', ROOT/'tests/selfhost-compiler-complete/toolchain.py', '--compiler', a.compiler, '--receipt', leaf/'toolchain.json'], 'toolchain')
	sources = {name: (ROOT/name).read_bytes() for name in ('compiler/ssa/recover.astra', 'compiler/cfg/recover-model.astra', 'compiler/backend/llvm/recover-module.astra')}
	ssa, cfg, emitter = sources.values()
	kernel = cfg[cfg.index(b'struct RecoverBlock {'):cfg.index(b'struct RecoverRegion {')]
	kernel += ssa[ssa.index(b'class RecoverWork {'):ssa.index(b'class RecoverSsaData {')]
	kernel += ssa[ssa.index(b'int recover_ssa_dominance_order('):ssa.index(b'int recover_ssa_definition(')]
	kernel += emitter[emitter.index(b'int recover_llvm_emission_order('):emitter.index(b'struct RecoverRecordStorage {')]
	view = leaf/'production-kernel.astra'; view.write_bytes(kernel)
	full_declarations = []
	for name, raw in sources.items():
		saved = leaf/Path(name).name; saved.write_bytes(raw)
		full_declarations.extend(declarations(run([a.compiler, '--dump-syntax', saved], saved.stem+'-syntax').decode()))
	selected = declarations(run([a.compiler, '--dump-syntax', view], 'kernel-syntax').decode())
	assert len(selected) == 6 and all(full_declarations.count(row) == 1 for row in selected)
	driver = Path(__file__).with_suffix('.astra'); saved_driver = leaf/driver.name; saved_driver.write_bytes(driver.read_bytes())
	(leaf/'recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	observer = leaf/'observer.c'; observer.write_text('#include <stdio.h>\nvoid dominance_observed(int work) { printf("%d\\n", work); }\n')
	objects = []
	for name, source in [('observer', observer), ('args', ROOT/'lib/runtime/platform/args-posix.c')]:
		obj = build/(name+'.o'); run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', source, '-o', obj], name+'-build'); objects.extend(['--link-object', obj])
	products = []
	for mode in ('O0', 'O2'):
		exe = build/('dominance-'+mode)
		run([a.compiler, '-'+mode, view, saved_driver, *objects, '-o', exe], mode+'-build')
		work = None
		for test in ('exhaustive', 'generated', 'chain'):
			out = run([exe, '--'+test], mode+'-'+test, 42)
			if test == 'chain':
				work = int(out); assert 0 < work < 80000
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe, '--'+test], mode+'-'+test+'-memory', 42)
			assert memory == out
			assert all(token in (leaf/(mode+'-'+test+'-memory.stderr')).read_bytes() for token in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		products.append(dict(profile=mode, ELF_sha256=sha(exe), exhaustive_graphs=15002, exhaustive_dominance_queries=237409, generated_graphs=4096, mixed_function_graphs=1, chain_nodes=8192, chain_queries=2048, chain_work=work, clean_memory_streams=3))
	assert all((ROOT/name).read_bytes() == raw for name, raw in sources.items()) and driver.read_bytes() == saved_driver.read_bytes()
	write(leaf/'result.json', dict(status='EXACT_PRODUCTION_DOMINANCE_KERNEL_PASS', production_sources={name: sha(ROOT/name) for name in sources}, normalized_production_AST=selected, kernel_sha256=sha(view), driver_sha256=sha(driver), products=products, full_original_native_profiles_proved=0, limitation='Exact production dominance and emission-order bodies execute under original C0. Graph deletion and recursive DFS are independent small-graph oracles. This is focused kernel evidence; integrated SSA, full compiler native objects and whole-module performance require separate receipts. Work ceiling remains 8,000,000.'))
	print('EXACT_PRODUCTION_DOMINANCE_KERNEL_PASS', flush=True)


if __name__ == '__main__':
	main()
