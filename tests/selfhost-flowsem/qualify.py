#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Portable focused qualification, with explicit out-of-source destinations."""
import argparse
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	for path in (a.build,a.runtime):
		assert not path.resolve().is_relative_to(ROOT), 'generated products require external paths'
	leaf = a.runtime/('qualification-'+str(time.time_ns()))
	subprocess.run([sys.executable,'-B',str(HERE/'freeze.py'),'--compiler',str(a.compiler),'--runtime',str(leaf/'frozen')],check=True)
	subprocess.run([sys.executable,'-B',str(HERE/'run.py'),'--compiler',str(a.compiler),'--build',str(a.build),'--runtime',str(leaf/'native'),'--baseline',str(leaf/'frozen')],check=True)


if __name__=='__main__':
	main()
