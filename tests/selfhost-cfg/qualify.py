#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Portable bounded CFG qualification; explicit external source-exact products."""
import argparse
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	leaf = a.runtime/('qualification-'+str(time.time_ns()))
	def run(script, *args):
		subprocess.run([sys.executable, '-B', HERE/script, *map(str, args)], check=True)
	run('build.py', '--compiler', a.compiler, '--build', a.build, '--runtime', leaf/'build')
	run('freeze.py', '--compiler', a.compiler, '--core', a.build, '--core2', a.build, '--core-prefix', 'astra-cfg-', '--runtime', leaf/'frozen', '--build', a.build/'reference')
	run('reference.py', '--compiler', a.compiler, '--build', a.build/'order-reference', '--runtime', leaf/'order-reference', '--frozen', leaf/'frozen')
	run('runtime_order.py', '--compiler', a.compiler, '--build', a.build/'runtime-order', '--runtime', leaf/'runtime-order', '--frozen', leaf/'frozen')
	run('run.py', '--build', a.build, '--runtime', leaf/'runs', '--frozen', leaf/'frozen')
	run('bounds.py', '--compiler', a.compiler, '--build', a.build, '--runtime', leaf/'bounds', '--frozen', leaf/'frozen')
	run('memory.py', '--build', a.build, '--runtime', leaf/'memory', '--frozen', leaf/'frozen', '--reference', a.build/'reference')
	subprocess.run([sys.executable, '-B', ROOT/'tests/selfhost-coreir/reference.py', '--compiler', a.compiler, '--build', a.build/'core-reference', '--runtime', leaf/'core-reference', '--baseline', leaf/'frozen/core/frozen', '--additional', leaf/'frozen/core/additional-frozen'], check=True)


if __name__ == '__main__':
	main()
