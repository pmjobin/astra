#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Use the established exact-product builder for the native flow consumer."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('typecore_build',ROOT/'tests/selfhost-typecore/build.py')
base=importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
sha=base.sha


def build(compiler,directory,capture,modes=('O0','O2')):
	return base.build(compiler,directory,capture,modes,consumer=ROOT/'tests/selfhost-ownflow/query.astra',with_flow=True)


if __name__=='__main__':
	p=argparse.ArgumentParser()
	p.add_argument('--compiler',type=Path,required=True)
	p.add_argument('--build',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	p.add_argument('--mode',action='append')
	a=p.parse_args()
	a.runtime.mkdir(parents=True,exist_ok=True)
	attempt=a.runtime/('build-'+str(time.time_ns()))
	attempt.mkdir()
	def capture(argv,name,details=None):
		if argv is None:
			(attempt/(name+'.json')).write_text(json.dumps(details,indent=2)+'\n')
			return b''
		start=time.monotonic()
		r=subprocess.run(list(map(str,argv)),cwd=a.build,capture_output=True,env=dict(os.environ,CCACHE_DISABLE='1'))
		(attempt/(name+'.stdout')).write_bytes(r.stdout)
		(attempt/(name+'.stderr')).write_bytes(r.stderr)
		(attempt/(name+'.json')).write_text(json.dumps(dict(argv=list(map(str,argv)),exit=r.returncode,seconds=time.monotonic()-start),indent=2)+'\n')
		print(name,r.returncode,flush=True)
		assert r.returncode==0,r.stderr.decode(errors='replace')[-5000:]
		return r.stdout
	products=build(a.compiler.resolve(),a.build.resolve(),capture,a.mode or ('O0','O2'))
	(attempt/'products.json').write_text(json.dumps(products,indent=2)+'\n')
