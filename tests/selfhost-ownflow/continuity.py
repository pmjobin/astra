#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused executed parser/lexer continuity on exactly pinned existing products."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from build import ROOT,sha


def verify_product(path):
	x=json.loads(path.with_suffix('.identity.json').read_text())
	assert sha(path)==x.get('sha256',x.get('product_sha256'))
	providers=[]
	for field in ('sources','tools','inputs'):
		for source,digest in x['identity'].get(field,{}).items():
			assert sha(source)==digest,(path,source,'exact product drift')
			dependency=Path(source)
			if dependency.suffix=='.o' and dependency.with_suffix('.identity.json').is_file():
				providers.append(verify_product(dependency))
	return dict(path=str(path),sha256=sha(path),identity_sha256=sha(path.with_suffix('.identity.json')),providers=providers)


def main():
	p=argparse.ArgumentParser()
	p.add_argument('--compiler',type=Path,required=True)
	p.add_argument('--runtime',type=Path,required=True)
	p.add_argument('--baseline',type=Path,required=True)
	p.add_argument('--parser-build',type=Path,required=True)
	p.add_argument('--lexer-build',type=Path,required=True)
	a=p.parse_args()
	a.runtime.mkdir(parents=True,exist_ok=False)
	rows=[]
	products=[]
	parser=a.parser_build
	lexer=a.lexer_build
	for path in [parser/'astra-bind-O0',parser/'astra-bind-O2',lexer/'lexer-O0',lexer/'lexer-O2',lexer/'lexer-oracle']:
		products.append(verify_product(path))
	entries=json.loads((a.baseline/'frozen.json').read_text())
	files=[]
	for case in ['pointer-store-escape','shortcircuit-state','class-heap-parameter-release','fallible-call','buffer-index-copy','nested-scalar-context','class-typed-move']:
		item=next(x for x in entries if x['name']==case)
		files+=item['paths']
	unicode=a.runtime/'unicode.astra'
	unicode.write_bytes('// é😀\r\nint f(){return 1;}\n'.encode())
	files.append(str(unicode))
	def run(argv,name,expected=0):
		start=time.monotonic()
		r=subprocess.run(list(map(str,argv)),cwd=ROOT,capture_output=True)
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout)
		(a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		rows.append(dict(name=name,argv=list(map(str,argv)),exit=r.returncode,seconds=time.monotonic()-start))
		assert r.returncode==expected,(name,r.stderr.decode()[-2500:])
		return r
	try:
		original=run([lexer/'lexer-oracle',*files],'lexer-reference').stdout
		for mode in ('O0','O2'):
			lex=lexer/('lexer-'+mode)
			parse=parser/('astra-bind-'+mode)
			assert run([lex,*files],'lexer-'+mode).stdout==original
			run([lex,'--lifetime'],'lexer-lifetime-'+mode)
			for option in ('--lifetime',):
				run([parse,option],'parser-'+option[2:]+'-'+mode)
			for n,path in enumerate(files):
				r=run([parse,'--syntax',path],'parser-'+str(n)+'-'+mode)
				assert r.stdout==run([a.compiler,'--dump-syntax',path],'syntax-reference-'+str(n)+'-'+mode).stdout
			for label,exe in [('lexer',lex),('parser',parse)]:
				r=run(['valgrind','--error-exitcode=97','--leak-check=full','--show-leak-kinds=all','--errors-for-leak-kinds=definite,indirect,possible',exe,'--lifetime'],'memory-'+label+'-'+mode)
				assert b'ERROR SUMMARY: 0 errors' in r.stderr
	finally:
		(a.runtime/'commands.json').write_text(json.dumps(rows,indent=2)+'\n')
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS',products=products,cases=files,commands=len(rows)),indent=2)+'\n')
	print('PASS parser/lexer continuity',len(rows),'commands')


if __name__=='__main__':
	main()
