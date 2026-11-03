#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Portable focused Core qualification; explicit external products and receipts."""
import argparse
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--baseline', type=Path)
	p.add_argument('--additional', type=Path)
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	assert bool(a.baseline) == bool(a.additional)
	leaf = a.runtime/('qualification-'+str(time.time_ns()))
	def run(script, *args):
		subprocess.run([sys.executable, '-B', HERE/script, *map(str, args)], check=True)
	run('build.py', '--compiler', a.compiler, '--build', a.build, '--runtime', leaf/'build')
	if a.baseline is None:
		run('freeze.py', '--compiler', a.compiler, '--admission', a.build/'astra-core-O0', '--runtime', leaf/'reference')
		a.baseline = leaf/'reference/frozen'
		a.additional = leaf/'reference/additional-frozen'
	run('run.py', '--compiler', a.compiler, '--build', a.build, '--runtime', leaf/'runs', '--baseline', a.baseline, '--additional', a.additional)
	run('reference.py', '--compiler', a.compiler, '--build', a.build/'reference', '--runtime', leaf/'reference-execution', '--baseline', a.baseline, '--additional', a.additional)


if __name__ == '__main__':
	main()
