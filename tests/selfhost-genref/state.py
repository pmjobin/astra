#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exact GENREF intake, protected state and original source-consumer replay."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = ROOT.parent/'codex/work/astra/runtime/genref24'
BUILD = ROOT.parent/'codex/work/astra/build/genref24'
PRIOR = RUNTIME.parent/'callplace23'
C0 = BUILD.parent/'llvm23-migration/production-final/astrac'
BASE = '6a9d99fab42a8ff49a92801625fe0b4d799b9faf'
TREE = '9ef70582645dd5b356bc7327c57ed4d30fbd7dd4'
REPORT = 'ba6ff507734ff831ef7770f9e9e0ad141b3472a4524e541cee477f8b4bde88cb'
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


def archive(path):
	with zipfile.ZipFile(path) as z:
		names = z.namelist(); assert len(names) == len(set(names)) and z.testzip() is None
		for row in z.infolist():
			p = Path(row.filename)
			assert not p.is_absolute() and '..' not in p.parts and '\\' not in row.filename and not row.is_dir()
			assert stat.S_IFMT(row.external_attr >> 16) in (0, stat.S_IFREG)
		manifest = json.loads(z.read('MANIFEST.json'))
		assert set(names) == {'MANIFEST.json'} | {row['path'] for row in manifest['files']}
		for row in manifest['files']:
			data = z.read(row['path']); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
	return dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path), entries=len(names))


def main():
	assert git('rev-parse', 'HEAD').strip() == BASE and git('rev-parse', 'HEAD^{tree}').strip() == TREE
	assert not git('diff', '--name-only') and not git('diff', '--cached', '--name-only')
	RUNTIME.mkdir(exist_ok=False); BUILD.mkdir(exist_ok=False)
	spec = importlib.util.spec_from_file_location('preservation', ROOT/'tests/selfhost-genresource/state.py')
	previous = importlib.util.module_from_spec(spec); spec.loader.exec_module(previous)
	result = previous.preservation(); old = read(PRIOR/'initial.json')
	assert all(sha(path) == expected for path, expected in old['workflow'].items())
	assert all(sha(path) == value['sha256'] and oct(Path(path).stat().st_mode & 0o777) == value['mode'] for path, value in old['hooks'].items())
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	assert sha(C0) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert report.stat().st_size == 21408478 and sha(report) == REPORT
	shutil.copy2(report, RUNTIME/'predecessor-report.zip')
	submission = ROOT.parent/'codex/submissions/ASTRA-SELFHOST-GENREF-24-SUBMISSION.zip'
	assert submission.stat().st_size == 128251 and sha(submission) == 'da4a2bf26f68ca23b3da9af4e60f2d83551945e269c15ebceea03910e3500b61'
	archives = [archive(submission), archive(report)]
	membercall = RUNTIME.parent/'callplace23/predecessor-report.zip'
	archives.append(archive(membercall))
	with zipfile.ZipFile(membercall) as z: assert json.loads(z.read('RESULT.json'))['status'] == 'PARTIAL'
	proofs = read(RUNTIME.parent/'indexpath18/historical-proof-outputs.json'); assert len(proofs['outputs']) == proofs['count'] == 1044
	assert all(sha(path) == row['sha256'] for path, row in proofs['outputs'].items())
	products = read(PRIOR/'final-audit.json')['products']
	for product in products.values():
		path = Path(product['path']); identity_path = path.with_suffix('.identity.json')
		assert sha(path) == product['sha256'] and sha(identity_path) == product['identity_sha256']
		identity = read(identity_path)['identity']
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity[group].items())
	result.update(base=BASE, tree=TREE, archives=archives, products=products, config=git('config', '--show-origin', '--list'), refs=git('show-ref'), worktrees=git('worktree', 'list', '--porcelain'), stash=git('stash', 'list'), status=git('status', '--porcelain=v2', '--untracked-files=all'), ignored=git('ls-files', '--others', '--ignored', '--exclude-standard'), hooks=old['hooks'], workflow=old['workflow'])
	(RUNTIME/'initial.json').write_text(json.dumps(result, indent=2)+'\n')
	print('Exact intake/protected/donor/history/C0/products verified', flush=True)
	replay()


def replay():
	assert git('rev-parse', 'HEAD').strip() == BASE
	cohorts = {}; references = read(PRIOR/'cohorts-v2.json')
	for name in COHORTS:
		prior = references[name]; ledger = read(PRIOR/('ledger-v2-'+name)/'ledger.json')
		logical, nodes = population(ledger)
		assert digest(logical) == prior['population_sha256'] and digest(nodes) == prior['node_identity_sha256']
		for row in ledger['files']:
			data = bytes.fromhex(row['synthetic_source_hex']) if 'synthetic_source_hex' in row else Path(row['path']).read_bytes()
			assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		leaf = RUNTIME/('baseline-v2-'+name); leaf.mkdir(); records = {}
		consumer = prior['independent_consumer']['argv'][2:]
		for label in ('ledger', 'consumer'):
			argv = consumer.copy()
			if label == 'ledger': argv[1] = '--classstorage-source-ledger'
			start = time.monotonic()
			with (leaf/(label+'.stdout')).open('xb') as out, (leaf/(label+'.stderr')).open('xb') as err:
				r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *argv], cwd=ROOT, stdout=out, stderr=err, timeout=240)
			records[label] = dict(argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(label+'.stdout')), stderr_sha256=sha(leaf/(label+'.stderr')))
			(leaf/'commands.json').write_text(json.dumps(records, indent=2)+'\n')
			assert r.returncode == 2
			if label == 'consumer': assert [line for line in (leaf/'consumer.stderr').read_text().splitlines() if line.startswith('CHECKED_CONSUMER')] == ['CHECKED_CONSUMER 1 7']
			else: assert sha(leaf/'ledger.stdout') == sha(PRIOR/('ledger-v2-'+name)/'whole-compiler.stdout')
		cohorts[name] = dict(files=len(ledger['files']), nodes=len(nodes), population_sha256=digest(logical), node_identity_sha256=digest(nodes), typed=prior['typed_after'], records=records)
		(RUNTIME/'baseline.json').write_text(json.dumps(cohorts, indent=2)+'\n')
		print(name, len(nodes), 'CHECKED_CONSUMER 1 7; exact ledger replay', flush=True)


if __name__ == '__main__':
	if sys.argv[1:] == ['--replay']: replay()
	else: main()
