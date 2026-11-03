#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Portable focused SSA qualification using explicit external build/runtime paths."""
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
	p.add_argument('--predecessor', type=Path, default=Path.home()/'Workspace/codex/work/astra/runtime/cfg10/frozen')
	p.add_argument('--cfg', type=Path, default=Path.home()/'Workspace/codex/work/astra/build/selfhost-cfg-10/qualified-final')
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime))
	assert (a.predecessor/'supplemental.json').is_file(), 'Provide the preserved CFG-10 input identities using --predecessor'
	assert (a.cfg/'astra-cfg-O0.identity.json').is_file(), 'Provide the qualified predecessor products using --cfg'
	leaf = a.runtime/('qualification-'+str(time.time_ns()))
	def run(script, *args):
		subprocess.run([sys.executable, '-B', HERE/script, *map(str, args)], check=True)
	run('build.py', '--compiler', a.compiler, '--build', a.build, '--runtime', leaf/'build')
	run('freeze.py', '--compiler', a.compiler, '--predecessor', a.predecessor, '--cfg', a.cfg, '--runtime', leaf/'frozen')
	run('run.py', '--build', a.build, '--runtime', leaf/'runs', '--frozen', leaf/'frozen')
	run('bounds.py', '--build', a.build, '--runtime', leaf/'bounds', '--frozen', leaf/'frozen')
	run('whole.py', '--build', a.build, '--runtime', leaf/'whole')
	run('memory.py', '--build', a.build, '--runtime', leaf/'memory', '--frozen', leaf/'frozen')
	run('reference.py', '--compiler', a.compiler, '--build', a.build/'reference', '--runtime', leaf/'reference', '--frozen', leaf/'frozen')


if __name__ == '__main__':
	main()
