#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute every Guide shell block verbatim with per-block output expectations."""
import argparse
import json
from pathlib import Path
import re
import shlex
import shutil
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
	chapters = json.loads((ROOT/'docs/chapters.json').read_text())['chapters']
	for chapter in chapters:
		if chapter.get('book') != 'guide': continue
		path = ROOT/'docs'/chapter['source']; sources[str(path)] = sha(path)
		assert len(re.findall(r'^```sh[^\n]*',path.read_text(),re.M)) == len(re.findall(r'^```sh tutorial=[a-z0-9-]+$',path.read_text(),re.M)),path
		for match in re.finditer(r'^```sh tutorial=([a-z0-9-]+)\n(.*?)^```$',path.read_text(),re.M|re.S):
			blocks.append((match[1],match[2]))
	expectations = Path(__file__).with_suffix('.json')
	spec = json.loads(expectations.read_text())['blocks']
	expected = [name for name,_ in blocks]
	assert len(expected) == len(set(expected)) and set(expected) == set(spec)
	# Keep one real shell: the setup's exports are prerequisites for later blocks.
	script = r/'tutorial.sh'
	program = ['set -eu\n']
	for name,body in blocks:
		leaf = r/'blocks'/name; leaf.mkdir(parents=True)
		(leaf/'source.sh').write_text(body)
		program.append('{\n'+body+'\ntest "$?" -eq 0\n} > '+shlex.quote(str(leaf/'stdout'))+' 2> '+shlex.quote(str(leaf/'stderr'))+'\n')
		program.append('printf "%s\\n" '+shlex.quote(name)+'\n')
	program.append('printf "%s\\n" "$ASTRA_BOOK_BUILD" > '+shlex.quote(str(r/'build-path'))+'\n')
	program.append('printf "%s\\n" "$ASTRA_CHECK_RUNTIME" > '+shlex.quote(str(r/'check-runtime-path'))+'\n')
	script.write_text(''.join(program))
	commands = []
	def run(label,argv,expected=0):
		result = execute(argv,r/label,expected=expected,timeout=1800)
		commands.append(dict(label=label,argv=list(map(str,argv)),result=result)); write(r/'commands.json',commands)
		assert result['status']=='EXPECTED_OUTCOME',(label,result)
		return result
	run('published-shell-blocks',['/bin/sh',str(script)])
	b = output_path(Path((r/'build-path').read_text().strip()),WORK/'build')
	observed = {}; provisional = False
	for name,body in blocks:
		leaf = r/'blocks'/name
		out = (leaf/'stdout').read_text().replace(str(b),'{build}').replace(str(ROOT),'{root}')
		err = (leaf/'stderr').read_text().replace(str(b),'{build}').replace(str(ROOT),'{root}')
		row = spec[name]
		if 'stdout_json' in row:
			data = json.loads(out)
			assert data['status'] == row['stdout_json'] and data['chapters'] == 30
			assert data['examples'] == len(json.loads((ROOT/'tests/books/examples.json').read_text())['cases'])
		else: assert out == row['stdout'],(name,out,row['stdout'])
		if 'stderr_contains' in row:
			assert row['stderr_contains'] in err,(name,err)
			provisional = True
		else: assert err == row['stderr'],(name,err,row['stderr'])
		observed[name] = dict(stdout=out,stderr=err,source_sha256=sha(leaf/'source.sh'),stdout_sha256=sha(leaf/'stdout'),stderr_sha256=sha(leaf/'stderr'))
	write(r/'observed.json',observed)
	assert not list(b.glob('rejected*.o'))
	selected = output_path(Path((r/'check-runtime-path').read_text().strip()),WORK/'runtime')/'run'
	shutil.copytree(selected,r/'selected-case-run')
	contracts = []
	for name in ('model-api.json','filtered-api.json'):
		symbols = json.loads((b/name).read_text())['symbols']
		by_name = {row['canonical_name']:row for row in symbols}
		assert {'Readings.Summary','Readings.Summary.count','Readings.Summary.total','Readings.summarize'} <= set(by_name)
		assert by_name['Readings.summarize']['parameters'][0]['type_contract']['ownership'] == 'borrowed_noescape'
		contracts.append([{key:row[key] for key in ('canonical_name','kind','signature','type_contract','parameters','throws')} for row in symbols])
	assert contracts[0] == contracts[1],'exercise changed the public calculation contract'
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
	write(r/'result.json',dict(status='TUTORIAL_AUTHORING_EXPECTATIONS_OBSERVED' if provisional else 'ACTUAL_PUBLISHED_TUTORIAL_COMMANDS_AND_SETUP_REFUSALS_PASS',blocks=expected,sources=sources,expectations_sha256=sha(expectations),observed_sha256=sha(r/'observed.json'),helper_sha256=sha(helper),recipe_sha256=sha(Path(__file__)),script_sha256=sha(script),commands_sha256=sha(r/'commands.json'),build=str(b),products={str(path):sha(path) for path in sorted(b.rglob('*')) if path.is_file()},scope='Every published Guide shell block, exact bytes in one /bin/sh -eu session; separate stdout/stderr per block. O0 compiler host with O0/O2 outputs; full matrix and memory separately qualified. A provisional diagnostic substring is authoring evidence only until the observed complete diagnostic is reviewed and frozen.'))
	print(len(blocks),'published shell blocks and two environment refusal controls passed')


if __name__ == '__main__':
	main()
