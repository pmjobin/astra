#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Portable affected qualification with explicit external build/runtime paths."""
import argparse
from pathlib import Path
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent


def main():
	p=argparse.ArgumentParser()
	for name in ('compiler','build','runtime'):
		p.add_argument('--'+name,type=Path,required=True)
	p.add_argument('--baseline',type=Path)
	a=p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build,a.runtime))
	leaf=a.runtime/('qualification-'+str(time.time_ns()))
	def run(script,*args):
		subprocess.run([sys.executable,'-B',str(script),*map(str,args)],check=True)
	run(ROOT/'tests/selfhost-flowsem/build.py','--compiler',a.compiler,'--build',a.build,'--runtime',leaf/'build')
	baseline=a.baseline or leaf/'frozen'
	if a.baseline is None:
		run(HERE/'freeze.py','--compiler',a.compiler,'--before',a.build/'astra-flow-O0','--runtime',baseline)
	run(HERE/'run.py','--compiler',a.compiler,'--build',a.build,'--runtime',leaf/'runs','--baseline',baseline)
	run(HERE/'reference.py','--compiler',a.compiler,'--build',a.build/'reference','--runtime',leaf/'reference','--baseline',baseline)


if __name__=='__main__':
	main()
