#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused continuity with fresh source/lexer products and the native binder parser."""
import argparse
import json
from pathlib import Path
import subprocess
import time

from build import ROOT, sha


def main():
	p=argparse.ArgumentParser()
	p.add_argument('--products',type=Path,required=True,help='Current binder products')
	p.add_argument('--compiler',type=Path,required=True)
	p.add_argument('--build',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	p.add_argument('--support-only',action='store_true')
	p.add_argument('--parser-only',action='store_true')
	a=p.parse_args()
	assert not (a.support_only and a.parser_only)
	assert not a.build.resolve().is_relative_to(ROOT)
	assert not a.runtime.resolve().is_relative_to(ROOT)
	a.build.mkdir(parents=True,exist_ok=True);a.runtime.mkdir(parents=True,exist_ok=True)
	attempt=a.runtime/('continuity-'+str(time.time_ns()));attempt.mkdir();rows=[]
	def run(argv,name,expected=0):
		start=time.monotonic();r=subprocess.run(list(map(str,argv)),capture_output=True,timeout=1200,cwd=attempt)
		rows.append(dict(argv=list(map(str,argv)),exit=r.returncode,seconds=time.monotonic()-start))
		(attempt/(name+'.stdout')).write_bytes(r.stdout);(attempt/(name+'.stderr')).write_bytes(r.stderr)
		(attempt/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
		assert r.returncode==expected,(name,r.returncode,r.stderr[-2000:]);return r.stdout
		# These ordinary maintained runners are rebuilt with the current compiler,
		# dependencies and host tools. Archived GCC identities are not silently reused.
	for component in (() if a.parser_only else ('foundation','lexer')):
		run(['python3','-B',ROOT/f'tests/selfhost-{component}/run.py','--compiler',a.compiler,'--build',a.build/component,'--runtime',attempt/component],component)
	if not a.parser_only:
		run(['python3','-B',ROOT/'tests/ecosystem-abi-8/layout-contexts.py',a.compiler,a.build/'layout'],'native-layout')
	if a.support_only:
		(attempt/'result.json').write_text(json.dumps(dict(status='PASS',phase='source-lexer-layout',compiler_sha256=sha(a.compiler)),indent=2)+'\n')
		print(attempt);return
	paths=[]
	for n,text in enumerate((b'int f(int p){return p+1;}',b'struct Box<T>{T value;}int f(){return 1;}',b'int f(){return \x00;}',b'int f( {return missing;}')):
		path=attempt/f'input-{n}.astra';path.write_bytes(text);paths.append(path)
	for n,path in enumerate(paths[:2]):
		expected=run([a.compiler,'--dump-syntax',path],f'parser-{n}-C0')
		for mode in ('O0','O2'):
			assert run([a.products/('astra-bind-'+mode),'--syntax',path],f'parser-{n}-{mode}')==expected
	for mode in ('O0','O2'):
		exe=a.products/('astra-bind-'+mode)
		assert run([exe,'--lifetime'],mode+'-lifetime')==b'BINDER_LIFETIME_OK\nPARSER_LIFETIME_OK\nPARSER_CURSOR_OK\n'
		for n,path in enumerate(paths[2:]):
			actual=run([exe,'--syntax',path],f'negative-{n}-{mode}',1)
			assert b'ERROR ' in actual
	(attempt/'result.json').write_text(json.dumps(dict(status='PASS',phase='parser' if a.parser_only else 'all',compiler_sha256=sha(a.compiler),scope='Fresh source/lexer component runners; binder parser syntax/diagnostic/lifetime controls; native-layout O0/O2 positive and deterministic negative.'),indent=2)+'\n')
	print(attempt)


if __name__=='__main__':main()
