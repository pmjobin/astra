#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay the installed Guide's current shell blocks, verbatim in one shell."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	with Path(path).open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	assert ROOT == Path('/usr/share/astra/tutorial'), 'run the installed recipe after clean package installation'
	assert a.runtime.is_absolute() and not a.runtime.resolve().is_relative_to(ROOT)
	r = a.runtime
	r.mkdir(parents=True, exist_ok=False)
	blocks = []
	sources = {}
	chapters = json.loads((ROOT/'docs/chapters.json').read_text())['chapters']
	for chapter in chapters:
		if chapter.get('book') != 'guide':
			continue
		path = ROOT/'docs'/chapter['source']
		sources[str(path.relative_to(ROOT))] = sha(path)
		body = path.read_text()
		assert len(re.findall(r'^```sh[^\n]*', body, re.M)) == len(re.findall(r'^```sh tutorial=[a-z0-9-]+$', body, re.M)), path
		blocks.extend((match[1], match[2]) for match in re.finditer(r'^```sh tutorial=([a-z0-9-]+)\n(.*?)^```$', body, re.M|re.S))
	expectations = Path(__file__).with_suffix('.json')
	spec = json.loads(expectations.read_text())['blocks']
	assert len(blocks) == len(set(name for name, _ in blocks)) and set(name for name, _ in blocks) == set(spec)
	script = r/'tutorial.sh'
	program = ['set -eu\n']
	for name, body in blocks:
		leaf = r/'blocks'/name
		leaf.mkdir(parents=True)
		(leaf/'source.sh').write_text(body)
		program.append('{\n'+body+'\ntest "$?" -eq 0\n} > '+shlex.quote(str(leaf/'stdout'))+' 2> '+shlex.quote(str(leaf/'stderr'))+'\n')
		program.append('printf "%s\\n" '+shlex.quote(name)+'\n')
	program.append('printf "%s\\n" "$ASTRA_BOOK_BUILD" > '+shlex.quote(str(r/'build-path'))+'\n')
	script.write_text(''.join(program))
	env = dict(os.environ, LC_ALL='C.UTF-8')
	for key in ('LD_LIBRARY_PATH', 'LD_PRELOAD', 'LIBRARY_PATH', 'CPATH'):
		env.pop(key, None)
	start = time.monotonic()
	result = subprocess.run(['/bin/sh', str(script)], capture_output=True, env=env, timeout=1800)
	(r/'stdout').write_bytes(result.stdout)
	(r/'stderr').write_bytes(result.stderr)
	(r/'command.json').write_text(json.dumps(dict(argv=['/bin/sh', str(script)], exit=result.returncode, seconds=time.monotonic()-start, stdout_sha256=sha(r/'stdout'), stderr_sha256=sha(r/'stderr')), indent=2)+'\n')
	assert result.returncode == 0, result.stderr.decode(errors='replace')
	b = Path((r/'build-path').read_text().strip())
	observed = {}
	for name, _ in blocks:
		leaf = r/'blocks'/name
		out = (leaf/'stdout').read_text().replace(str(b), '{build}').replace(str(ROOT), '{root}')
		err = (leaf/'stderr').read_text().replace(str(b), '{build}').replace(str(ROOT), '{root}')
		assert out == spec[name]['stdout'], (name, out, spec[name]['stdout'])
		assert err == spec[name]['stderr'], (name, err, spec[name]['stderr'])
		observed[name] = dict(stdout=out, stderr=err, source_sha256=sha(leaf/'source.sh'), stdout_sha256=sha(leaf/'stdout'), stderr_sha256=sha(leaf/'stderr'))
	assert not list(b.glob('rejected*.o'))
	contracts = []
	for name in ('model-api.json', 'filtered-api.json'):
		symbols = json.loads((b/name).read_text())['symbols']
		rows = {row['canonical_name']:row for row in symbols}
		assert {'Readings.Summary', 'Readings.Summary.count', 'Readings.Summary.total', 'Readings.summarize'} <= set(rows)
		assert rows['Readings.summarize']['parameters'][0]['type_contract']['ownership'] == 'borrowed_noescape'
		contracts.append([{key:row[key] for key in ('canonical_name', 'kind', 'signature', 'type_contract', 'parameters', 'throws')} for row in symbols])
	assert contracts[0] == contracts[1]
	(r/'observed.json').write_text(json.dumps(observed, indent=2)+'\n')
	receipt = dict(status='INSTALLED_GUIDE_VERBATIM_COMMANDS_PASS', blocks=[name for name, _ in blocks], sources=sources, expectations_sha256=sha(expectations), observed_sha256=sha(r/'observed.json'), script_sha256=sha(script), command_sha256=sha(r/'command.json'), recipe_sha256=sha(__file__), build=str(b), products={str(path.relative_to(b)):sha(path) for path in sorted(b.rglob('*')) if path.is_file()}, scope='All current sh tutorial blocks in the installed Guide; historical contributor console blocks are retained with their earlier qualification. Fresh O0/O2, real C providers, executable outcomes and exact diagnostics; separate strict-memory and four-profile Book matrix remain required.')
	(r/'result.json').write_text(json.dumps(receipt, indent=2)+'\n')
	print(len(blocks), 'installed Guide shell blocks passed')


if __name__ == '__main__':
	main()
