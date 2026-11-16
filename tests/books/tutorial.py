#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute the opening chapters' actual shell blocks and environment refusals."""
import argparse
import json
from pathlib import Path
import re
import shlex
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0,str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--runtime',type=Path,required=True)
	a = p.parse_args()
	r = output_path(a.runtime,WORK/'runtime'); r.mkdir(parents=True,exist_ok=False)
	blocks = []; sources = {}
	for name in ('getting-started','values','records'):
		path = ROOT/'docs/guide'/(name+'.md'); sources[str(path)] = sha(path)
		for match in re.finditer(r'^```sh tutorial=([a-z0-9-]+)\n(.*?)^```$',path.read_text(),re.M|re.S):
			blocks.append((match[1],match[2]))
	expected = ['setup','first','first-o2','failed-check','type-error','values','filter-answer','mixed-type-error','conversion-answer','records','label-error','weight-answer','generic-preview']
	assert [name for name,_ in blocks]==expected
	# Keep one real shell: the setup's exports are prerequisites for later blocks.
	script = r/'tutorial.sh'
	script.write_text('set -eu\n'+''.join(body+'\ntest "$?" -eq 0\n' for _,body in blocks)+'\nprintf "%s\\n" "$ASTRA_BOOK_BUILD" > '+shlex.quote(str(r/'build-path'))+'\n')
	commands = []
	def run(label,argv,expected=0):
		result = execute(argv,r/label,expected=expected,timeout=600)
		commands.append(dict(label=label,argv=list(map(str,argv)),result=result)); write(r/'commands.json',commands)
		assert result['status']=='EXPECTED_OUTCOME',(label,result)
		return result
	run('published-shell-blocks',['/bin/sh',str(script)])
	out = (r/'published-shell-blocks/stdout').read_text()
	for message in ('Readings check passed (exit 0).','Optimized readings check passed (exit 0).','check exit: 1','Five readings; total 30 (exit 0).','Four readings; total 24 (exit 0).','Converted sum is 42 (exit 0).','Weighted total and independent copy checks passed (exit 0).','Weighted total 40; copy checks passed (exit 0).','generic preview exit: 42'):
		assert out.splitlines().count(message)==1,message
	err = (r/'published-shell-blocks/stderr').read_text()
	for message in ("expected initializer of type 'bool', found 'int'","operator '+' requires compatible exact operand types",'named arguments require unique declared parameter labels and every required argument'):
		assert message in err,message
	b = output_path(Path((r/'build-path').read_text().strip()),WORK/'build')
	assert all(not (b/name).exists() for name in ('rejected.o','rejected-mix.o','rejected-label.o'))
	products = WORK/'runtime/api-docs28a1-products.json'
	toolchain = WORK/'runtime/selfhost27c-dev21/build-identity.json'
	helper = ROOT/'tests/books/environment.py'
	base = [sys.executable,'-B',str(helper),'--products',str(products),'--toolchain',str(toolchain)]
	environment_hash = sha(b/'environment.sh')
	run('existing-output-refused',[*base,'--output',str(b/'environment.sh')],1)
	assert sha(b/'environment.sh')==environment_hash
	assert 'File exists' in (r/'existing-output-refused/stderr').read_text()
	bad = r/'mismatched-products.json'; bad.write_bytes(products.read_bytes()+b'\n')
	argv = list(base); argv[argv.index('--products')+1] = str(bad)
	run('manifest-mismatch-refused',[*argv,'--output',str(b/'untrusted.sh')],1)
	assert not (b/'untrusted.sh').exists()
	assert 'manifest differs' in (r/'manifest-mismatch-refused/stderr').read_text()
	write(r/'result.json',dict(status='ACTUAL_PUBLISHED_TUTORIAL_COMMANDS_AND_SETUP_REFUSALS_PASS',blocks=expected,sources=sources,helper_sha256=sha(helper),recipe_sha256=sha(Path(__file__)),script_sha256=sha(script),commands_sha256=sha(r/'commands.json'),build=str(b),products={str(path):sha(path) for path in sorted(b.iterdir()) if path.is_file()},scope='Exact published shell block bytes in one /bin/sh -eu session, O0 compiler host with O0 and O2 outputs. Native host/target matrix and strict memory are separately qualified by tests/books/run.py. Refusals preserve an existing environment and produce no untrusted output.'))
	print(len(blocks),'published shell blocks and two environment refusal controls passed')


if __name__ == '__main__':
	main()
