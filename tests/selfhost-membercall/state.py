#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Preserve MEMBERCALL intake and reproduce the exact predecessor stops."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT.parent/'codex/work/astra/runtime/membercall22'
BUILD = ROOT.parent/'codex/work/astra/build/membercall22'
PRIOR = RUNTIME.parent/'slotswap21'
C0 = BUILD.parent/'llvm23-migration/production-final/astrac'
BASE = 'eb2c16956d7b5b282e11b92fa8c3bbc2672e91c7'
TREE = '6d23d48ad2024fdf321e974f298d75013fa83d57'
REPORT = '30ad8111039c15ab7ddba118b9368bb4c574c3caf96e90186974d682a2e1a7ae'
COHORTS = ('original', 'LLVM23-base', 'Class15-current', 'live-initial')


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def git(*args):
	return subprocess.check_output(['git', '--no-optional-locks', '-C', ROOT, *args]).decode()


def digest(value):
	return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def population(data):
	files = {row['path']: row for row in data['files']}
	logical = {row['relative']: (row['bytes'], row['sha256']) for row in data['files']}
	nodes = [[row['node'], row['syntax_kind'], files[row['path']]['relative'], row['start'], row['end'], row['source_sha256']] for row in data['nodes']]
	return logical, nodes


def main():
	assert git('rev-parse', 'HEAD').strip() == BASE and git('rev-parse', 'HEAD^{tree}').strip() == TREE
	assert git('diff', '--name-only') == git('diff', '--cached', '--name-only') == ''
	RUNTIME.mkdir(exist_ok=False); BUILD.mkdir(exist_ok=False)
	spec = importlib.util.spec_from_file_location('preservation', ROOT/'tests/selfhost-genresource/state.py')
	previous = importlib.util.module_from_spec(spec); spec.loader.exec_module(previous)
	result = previous.preservation()
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert report.stat().st_size == 18883640 and sha(report) == REPORT
	shutil.copy2(report, RUNTIME/'predecessor-report.zip')
	shutil.copytree(RUNTIME.parent/'native-current', RUNTIME/'predecessor-intake')
	with zipfile.ZipFile(report) as archive:
		assert archive.testzip() is None
		manifest = json.loads(archive.read('MANIFEST.json'))
		for row in manifest['files']:
			data = archive.read(row['path']); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	assert sha(C0) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	products = read(PRIOR/'final-audit.json')['products']
	for product in products.values():
		path = Path(product['path']); identity_path = path.with_suffix('.identity.json')
		assert sha(path) == product['sha256'] and sha(identity_path) == product['identity_sha256']
		identity = read(identity_path)['identity']
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity[group].items())
	cohorts = {}; references = read(PRIOR/'cohorts-v1.json')
	for name in COHORTS:
		old_leaf = PRIOR/('ledger-v1-'+name); old = read(old_leaf/'ledger.json')
		logical, nodes = population(old); reference = references[name]
		assert digest(logical) == reference['population_sha256'] and digest(nodes) == reference['node_identity_sha256']
		for row in old['files']:
			data = bytes.fromhex(row['synthetic_source_hex']) if 'synthetic_source_hex' in row else Path(row['path']).read_bytes()
			assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		argv = read(old_leaf/'commands.json')[-1]['argv'][2:]
		assert Path(argv[0]) == Path(products['O0']['path'])
		start = time.monotonic()
		with (RUNTIME/(name+'.stdout')).open('xb') as out, (RUNTIME/(name+'.stderr')).open('xb') as err:
			r = subprocess.run(['/usr/bin/time', '-v', '-o', RUNTIME/(name+'.time'), *argv], cwd=ROOT, stdout=out, stderr=err, timeout=300)
		assert r.returncode == 1 and sha(RUNTIME/(name+'.stdout')) == sha(old_leaf/'whole-compiler.stdout')
		cohorts[name] = dict(argv=argv, exit=r.returncode, start=start, end=time.monotonic(), files=len(old['files']), nodes=len(nodes), population_sha256=digest(logical), node_identity_sha256=digest(nodes), typed=sum(bool(row['type']) and row['deferred'] == 0 for row in old['nodes']), first_stop=old['diagnostics'][0], stdout_sha256=sha(RUNTIME/(name+'.stdout')))
		print(name, cohorts[name]['typed'], cohorts[name]['first_stop'], flush=True)
	workflow = Path.home()/'.agents/skills/pm-next'
	proofs = read(RUNTIME.parent/'indexpath18/historical-proof-outputs.json'); assert len(proofs['outputs']) == proofs['count'] == 1044
	assert all(sha(path) == row['sha256'] for path, row in proofs['outputs'].items())
	result.update(base=BASE, tree=TREE, cohorts=cohorts, predecessor_sha256=REPORT, products=products, config=git('config', '--show-origin', '--list'), refs=git('show-ref'), worktrees=git('worktree', 'list', '--porcelain'), stash=git('stash', 'list'), status=git('status', '--porcelain=v2', '--untracked-files=all'), ignored=git('ls-files', '--others', '--ignored', '--exclude-standard'), hooks={str(p): dict(sha256=sha(p), mode=oct(p.stat().st_mode & 0o777)) for p in (ROOT/'.git/hooks').iterdir()}, workflow={str(p): sha(p) for p in [workflow/'SKILL.md', *sorted((workflow/'scripts').glob('*.py'))]})
	(RUNTIME/'initial.json').write_text(json.dumps(result, indent=2)+'\n')
	print('Four exact first stops reproduced; 451 protected / 6622 donor / 1044 historical outputs preserved')


if __name__ == '__main__':
	main()
