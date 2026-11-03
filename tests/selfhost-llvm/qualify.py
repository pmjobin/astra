#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused LLVM component entry, with explicit external build/runtime routing."""
import argparse
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def main():
	p = argparse.ArgumentParser()
	for key in ('compiler','build','runtime'):
		p.add_argument('--'+key,type=Path,required=True)
	p.add_argument('--predecessor',type=Path,default=Path.home()/'Workspace/codex/work/astra/runtime/ssa11/frozen')
	p.add_argument('--mode',action='append',choices=('O0','O2'))
	a = p.parse_args()
	assert not a.build.resolve().is_relative_to(ROOT) and not a.runtime.resolve().is_relative_to(ROOT)
	attempt = a.runtime/('qualification-'+str(time.time_ns()))
	def run(script,*args):
		subprocess.run([sys.executable,'-B',str(script),*map(str,args)],check=True)
	run(HERE/'freeze.py','--predecessor',a.predecessor,'--runtime',attempt/'frozen')
	for mode in a.mode or ('O0','O2'):
		run(HERE/'build.py','--compiler',a.compiler,'--build',a.build,'--runtime',attempt/'build','--mode',mode)
		component = a.build/('astra-llvm-'+mode)
		run(HERE/'run.py','--component',component,'--compiler',a.compiler,'--build',a.build/'applications','--runtime',attempt/('runs-'+mode),'--frozen',attempt/'frozen','--mode',mode)
		run(HERE/'fatal.py','--component',component,'--compiler',a.compiler,'--build',a.build/'fatal','--runtime',attempt/('fatal-'+mode),'--frozen',attempt/'frozen','--mode',mode)
		run(HERE/'negative.py','--component',component,'--runtime',attempt/('negative-'+mode),'--frozen',attempt/'frozen','--mode',mode)
		run(ROOT/'tests/selfhost-ssa/run.py','--build',a.build,'--runtime',attempt/('continuity-'+mode),'--frozen',a.predecessor,'--mode',mode,'--product-prefix','astra-llvm-')


if __name__ == '__main__':
	main()
