#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact production SSA lookup kernel versus an independent occurrence oracle."""
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
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	a = p.parse_args(); assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = a.runtime_root/('ssa-index-'+a.version); build = a.build_root/leaf.name; leaf.mkdir(); build.mkdir()
	source = ROOT/'compiler/ssa/recover.astra'; raw = source.read_bytes()
	work = raw[raw.index(b'class RecoverWork {'):raw.index(b'class RecoverSsaData {')]
	kernel = raw[raw.index(b'owned int[] recover_ssa_local_definitions('):raw.index(b'bool recover_ssa_verify(')]
	view = leaf/'actual-kernel.astra'; view.write_bytes(work+kernel)
	driver = Path(__file__).with_name('ssa-index-driver.astra'); saved_driver = leaf/driver.name; saved_driver.write_bytes(driver.read_bytes())
	(leaf/'production-source.astra').write_bytes(raw); (leaf/'recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	observer = leaf/'observer.c'; observer.write_text('#include <stdio.h>\nvoid observed(int n,int c,int a,int b,int d,int r,int e) { printf("%d %d %d %d %d %d %d\\n",n,c,a,b,d,r,e); }\n')
	commands = []; env = dict(os.environ, CCACHE_DISABLE='1')
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
	full_ast = run([a.compiler, '--dump-syntax', leaf/'production-source.astra'], 'full-syntax')
	view_ast = run([a.compiler, '--dump-syntax', view], 'view-syntax')
	rows = declarations(full_ast.decode()); selected = declarations(view_ast.decode())
	assert len(selected) == 2 and all(rows.count(actual) == 1 for actual in selected)
	obj = build/'observer.o'; run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', observer, '-o', obj], 'observer-build')
	expected = []
	for n in range(7):
		for code in range(4**n):
			digits = [(code//(4**i)) % 4 for i in range(n)]
			values = []
			for symbol in (1, 2, 3):
				positions = [i+1 for i, digit in enumerate(digits) if digit == symbol]
				values.append(0 if not positions else positions[0] if len(positions) == 1 else -1)
			expected.append([n, code, *values, 8000000-n, 0])
	expected.extend([[8192, -1, 1, 4096, 8192, 8000000-8192, 0], [4, -2, 1, 2, 0, 0, 1], [4, -3, 1, 2, 4, 0, 0], [4, -4, 0, 0, 0, 0, 1], [4, -5, 0, 0, 0, 8000001, 1], [2, -6, 2, 0, 0, 7999998, 0], [2, -7, -1, 0, 0, 7999998, 0]])
	products = []
	for mode in ('O0', 'O2'):
		exe = build/('ssa-index-'+mode); run([a.compiler, '-'+mode, view, saved_driver, '--link-object', obj, '-o', exe], mode+'-build')
		out = run([exe], mode+'-execute', 42); actual = [[int(value) for value in line.split()] for line in out.splitlines()]; assert actual == expected
		memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], mode+'-memory', 42); assert memory == out
		assert all(token in (leaf/(mode+'-memory.stderr')).read_bytes() for token in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		products.append(dict(mode=mode, ELF_sha256=sha(exe), rows=len(actual), exit=42, unsuppressed_memory=True))
	assert source.read_bytes() == raw and driver.read_bytes() == saved_driver.read_bytes()
	write(leaf/'result.json', dict(status='C0_KERNEL_PASS', production_source_sha256=sha(source), actual_kernel_sha256=sha(view), normalized_production_AST=selected, exhaustive_graphs=sum(4**n for n in range(7)), boundary_and_order_cases=7, largest_rows=8192, actual_largest_index_work=8192, legacy_full_scan_visits_for_8192_reads=8192**2, products=products, target_native_credit=0, limitation='Only exact production index/work kernels execute under C0 using minimal field containers and an independent occurrence oracle. No verified compiler CFG, integrated SSA/Astra native source qualification, whole compiler performance or speedup is proved. The 8,000,000 ceiling is unchanged.'))
	print('C0_KERNEL_PASS', len(expected), 'rows/profile', flush=True)


if __name__ == '__main__':
	main()
