#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Create a deterministic, licensed source snapshot and SRPM from a full Git pin."""
import argparse
import datetime
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile

from common import ROOT, external, require, sha, verify, write

SEED = dict(bytes=2388496, sha256='560e7c9eaeb6cdb974efdd43ed4ac41191cdda4acdb4afd77052325addf1f1c6')
SEED_PATH = 'tools/ci/seeds/astra-27d-stage3-o2-linux-x86_64.elf'
PREFIXES = ('compiler/', 'lib/', 'docs/', 'tests/books/', 'tests/install/', 'tools/docs/', 'tools/ci/', 'packaging/rpm/', '.copr/')
LICENSES = ('LICENSE.txt', 'tools/ci/seeds/LICENSE.txt', 'tools/ci/seeds/PROVENANCE.json')
BOOK_WITNESSES = ('tests/selfhost-convergence-27d/c-client.py', 'tests/selfhost-expressive-language-27c/named.py')


def selected(name):
	return (name in LICENSES or name in BOOK_WITNESSES or name.startswith(PREFIXES)) and name != SEED_PATH


def git(*args):
	return subprocess.check_output(['git', '-C', ROOT, *args])


def snapshot(commit):
	require(re.fullmatch('[0-9a-f]{40}', commit), 'full Git commit required')
	require(git('rev-parse', 'HEAD').decode().strip() == commit, 'checkout identity mismatch')
	rows = git('ls-tree', '-rz', commit).split(b'\0')
	entries = {}
	for row in filter(None, rows):
		meta, raw = row.split(b'\t', 1)
		mode, kind, oid = meta.decode().split()
		name = raw.decode()
		if selected(name) or name == SEED_PATH:
			require(kind == 'blob' and mode in ('100644', '100755'), 'nonregular source: '+name)
			entries[name] = (mode, oid)
	dirty = git('diff', '--name-only', 'HEAD').decode().splitlines()
	require(not any(selected(n) or n == SEED_PATH for n in dirty), 'commit source changes before packaging')
	request = ''.join(oid+'\n' for mode, oid in entries.values()).encode()
	stream = io.BytesIO(subprocess.check_output(['git', '-C', ROOT, 'cat-file', '--batch'], input=request))
	files = {}
	for name, (mode, oid) in entries.items():
		got, kind, size = stream.readline().decode().split()
		require(got == oid and kind == 'blob', 'Git source transport mismatch')
		data = stream.read(int(size))
		require(stream.read(1) == b'\n', 'Git source transport truncated')
		files[name] = (mode, data)
	seed = files.pop(SEED_PATH)[1]
	require(len(seed) == SEED['bytes'] and hashlib.sha256(seed).hexdigest() == SEED['sha256'], 'seed identity mismatch')
	for name in LICENSES:
		require(name in files and files[name][1], 'missing source license/provenance: '+name)
	rules = json.loads(files['docs/books/rules.json'][1])
	book_inputs = {row['path'] for rule in rules['rules'] for kind in ('sources', 'positive', 'negative') for row in rule[kind]}
	require(book_inputs <= files.keys(), 'incomplete Book source witnesses: '+str(sorted(book_inputs-files.keys())))
	for name, (mode, data) in files.items():
		require(not name.endswith(('.o', '.a', '.so', '.rpm', '.elf')) and not data.startswith((b'\x7fELF', b'!<arch>')), 'prebuilt input refused: '+name)
	return files, seed


def archive(commit, output):
	files, seed = snapshot(commit)
	tree = git('rev-parse', commit+'^{tree}').decode().strip()
	epoch = int(git('show', '-s', '--format=%ct', commit))
	manifest = dict(format='astra-copr-source/1', commit=commit, tree=tree, epoch=epoch, qualification='DEVELOPMENT_UNQUALIFIED', seed=SEED, licenses=list(LICENSES), files={n:dict(bytes=len(b), sha256=hashlib.sha256(b).hexdigest(), mode=m) for n, (m, b) in sorted(files.items())})
	data = json.dumps(manifest, indent=2, sort_keys=True).encode()+b'\n'
	files['SOURCE-MANIFEST.json'] = ('100644', data)
	path = output/('astra-'+commit+'.tar.gz')
	with path.open('xb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as compressed, tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as tar:
		for name, (mode, data) in sorted(files.items()):
			info = tarfile.TarInfo('astra-'+commit+'/'+name)
			info.size, info.mtime, info.mode = len(data), epoch, int(mode, 8) & 0o777
			tar.addfile(info, io.BytesIO(data))
	(output/Path(SEED_PATH).name).write_bytes(seed)
	return path, manifest


def verify_source(commit, tree):
	m = json.loads((ROOT/'SOURCE-MANIFEST.json').read_text())
	require(m['format'] == 'astra-copr-source/1' and m['commit'] == commit and m['tree'] == tree, 'source commit/tree mismatch')
	require(m['seed'] == SEED and m['licenses'] == list(LICENSES), 'source licensing/seed contract mismatch')
	actual = {str(p.relative_to(ROOT)) for p in ROOT.rglob('*') if p.is_file() or p.is_symlink()}
	require(actual == set(m['files']) | {'SOURCE-MANIFEST.json'}, 'missing or undeclared source input')
	for name, pin in m['files'].items():
		require(selected(name) and not Path(name).is_absolute() and '..' not in Path(name).parts, 'source outside public closure')
		verify(ROOT/name, pin)
	for name in LICENSES:
		require(name in m['files'] and (ROOT/name).stat().st_size, 'missing license/provenance')
	return m


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--commit', required=True)
	p.add_argument('--output', required=True, type=Path)
	p.add_argument('--spec', default='packaging/rpm/astrac.spec')
	p.add_argument('--archive-only', action='store_true')
	a = p.parse_args()
	require(a.spec == 'packaging/rpm/astrac.spec', 'wrong spec/package requested')
	output = external(a.output, fresh=False)
	top = output/('srpm-'+a.commit)
	top.mkdir()
	sources = top/'SOURCES'
	sources.mkdir()
	path, manifest = archive(a.commit, sources)
	template = git('show', a.commit+':'+a.spec).decode()
	require(re.search(r'^Name:\s+astrac$', template, re.M), 'wrong package name')
	values = dict(COMMIT=a.commit, TREE=manifest['tree'], SHORT=a.commit[:12], DATE=datetime.datetime.fromtimestamp(manifest['epoch'], datetime.timezone.utc).strftime('%Y%m%d%H%M%S'), SOURCE_SHA=sha(path))
	for key, value in values.items():
		template = template.replace('@'+key+'@', value)
	spec = top/'astrac.spec'
	spec.write_text(template)
	write(top/'source-receipt.json', dict(commit=a.commit, tree=manifest['tree'], source_sha256=sha(path), seed=SEED, licenses=list(LICENSES), manifest=manifest))
	if not a.archive_only:
		env = dict(os.environ, SOURCE_DATE_EPOCH=str(manifest['epoch']))
		subprocess.run(['rpmbuild', '-bs', '--define', '_topdir '+str(top), '--define', '_srcrpmdir '+str(output), '--define', '_buildhost astra-source.invalid', '--define', 'source_date_epoch_from_changelog 0', '--define', 'use_source_date_epoch_as_buildtime 1', str(spec)], check=True, env=env)
		artifacts = list(output.glob('astrac-*.src.rpm'))
		require(len(artifacts) == 1, 'ambiguous source RPM output')
		subprocess.run(['rpm', '-qpl', artifacts[0]], check=True)
		write(top/'srpm-receipt.json', dict(commit=a.commit, source_sha256=sha(path), seed=SEED, srpm=dict(name=artifacts[0].name, bytes=artifacts[0].stat().st_size, sha256=sha(artifacts[0]))))
	print('SOURCE_SNAPSHOT_CREATED', a.commit, sha(path))


if __name__ == '__main__':
	main()
