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
RHEL9_SEED_PATH = 'tools/ci/seeds/astra-rhel9-llvm22-x86_64.elf'
RHEL9_PROVENANCE = 'tools/ci/seeds/RHEL9-PROVENANCE.json'
PREFIXES = ('compiler/', 'lib/', 'docs/', 'tests/books/', 'tests/install/', 'tools/docs/', 'tools/ci/', 'packaging/rpm/', '.copr/')
LICENSES = ('LICENSE.txt', 'tools/ci/seeds/LICENSE.txt', 'tools/ci/seeds/PROVENANCE.json')
BOOK_WITNESSES = ('tests/selfhost-convergence-27d/c-client.py', 'tests/selfhost-expressive-language-27c/named.py')


def selected(name):
	return (name in LICENSES or name in BOOK_WITNESSES or name.startswith(PREFIXES)) and name not in (SEED_PATH, RHEL9_SEED_PATH)


def seed_contract(target):
	if target is None:
		return SEED, SEED_PATH, LICENSES
	require(target == 'rhel9', 'unsupported source RPM target')
	provenance = json.loads((ROOT/RHEL9_PROVENANCE).read_bytes())
	require(provenance['format'] == 'astra-rhel9-seed-provenance/1', 'wrong RHEL 9 seed provenance format')
	return provenance['seed'], RHEL9_SEED_PATH, (*LICENSES, RHEL9_PROVENANCE)


def git(*args):
	return subprocess.check_output(['git', '-C', ROOT, *args])


def snapshot(commit, rhel9_seed=None):
	require(re.fullmatch('[0-9a-f]{40}', commit), 'full Git commit required')
	require(git('rev-parse', 'HEAD').decode().strip() == commit, 'checkout identity mismatch')
	rows = git('ls-tree', '-rz', commit).split(b'\0')
	entries = {}
	for row in filter(None, rows):
		meta, raw = row.split(b'\t', 1)
		mode, kind, oid = meta.decode().split()
		name = raw.decode()
		if selected(name) or (name == SEED_PATH and rhel9_seed is None):
			require(kind == 'blob' and mode in ('100644', '100755'), 'nonregular source: '+name)
			entries[name] = (mode, oid)
	dirty = git('diff', '--name-only', 'HEAD').decode().splitlines()
	require(not any(selected(n) or n in (SEED_PATH, RHEL9_SEED_PATH) for n in dirty), 'commit source changes before packaging')
	request = ''.join(oid+'\n' for mode, oid in entries.values()).encode()
	stream = io.BytesIO(subprocess.check_output(['git', '-C', ROOT, 'cat-file', '--batch'], input=request))
	files = {}
	for name, (mode, oid) in entries.items():
		got, kind, size = stream.readline().decode().split()
		require(got == oid and kind == 'blob', 'Git source transport mismatch')
		data = stream.read(int(size))
		require(stream.read(1) == b'\n', 'Git source transport truncated')
		files[name] = (mode, data)
	pin, seed_path, licenses = seed_contract('rhel9' if rhel9_seed else None)
	seed = verify(rhel9_seed, pin).read_bytes() if rhel9_seed else files.pop(seed_path)[1]
	require(len(seed) == pin['bytes'] and hashlib.sha256(seed).hexdigest() == pin['sha256'], 'seed identity mismatch')
	for name in licenses:
		require(name in files and files[name][1], 'missing source license/provenance: '+name)
	rules = json.loads(files['docs/books/rules.json'][1])
	book_inputs = {row['path'] for rule in rules['rules'] for kind in ('sources', 'positive', 'negative') for row in rule[kind]}
	require(book_inputs <= files.keys(), 'incomplete Book source witnesses: '+str(sorted(book_inputs-files.keys())))
	for name, (mode, data) in files.items():
		require(not name.endswith(('.o', '.a', '.so', '.rpm', '.elf')) and not data.startswith((b'\x7fELF', b'!<arch>')), 'prebuilt input refused: '+name)
	return files, seed


def archive(commit, output, rhel9_seed=None):
	files, seed = snapshot(commit, rhel9_seed)
	target = 'rhel9' if rhel9_seed else None
	pin, seed_path, licenses = seed_contract(target)
	tree = git('rev-parse', commit+'^{tree}').decode().strip()
	epoch = int(git('show', '-s', '--format=%ct', commit))
	manifest = dict(format='astra-copr-source/1', commit=commit, tree=tree, epoch=epoch, qualification='DEVELOPMENT_UNQUALIFIED', seed=pin, licenses=list(licenses), files={n:dict(bytes=len(b), sha256=hashlib.sha256(b).hexdigest(), mode=m) for n, (m, b) in sorted(files.items())})
	if target:
		manifest['target'] = target
	data = json.dumps(manifest, indent=2, sort_keys=True).encode()+b'\n'
	files['SOURCE-MANIFEST.json'] = ('100644', data)
	path = output/('astra-'+commit+'.tar.gz')
	with path.open('xb') as raw, gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0, compresslevel=9) as compressed, tarfile.open(fileobj=compressed, mode='w', format=tarfile.PAX_FORMAT) as tar:
		for name, (mode, data) in sorted(files.items()):
			info = tarfile.TarInfo('astra-'+commit+'/'+name)
			info.size, info.mtime, info.mode = len(data), epoch, int(mode, 8) & 0o777
			tar.addfile(info, io.BytesIO(data))
	(output/Path(seed_path).name).write_bytes(seed)
	return path, manifest


def verify_source(commit, tree):
	m = json.loads((ROOT/'SOURCE-MANIFEST.json').read_text())
	require(m['format'] == 'astra-copr-source/1' and m['commit'] == commit and m['tree'] == tree, 'source commit/tree mismatch')
	pin, _, licenses = seed_contract(m.get('target'))
	require(m['seed'] == pin and m['licenses'] == list(licenses), 'source licensing/seed contract mismatch')
	actual = {str(p.relative_to(ROOT)) for p in ROOT.rglob('*') if p.is_file() or p.is_symlink()}
	require(actual == set(m['files']) | {'SOURCE-MANIFEST.json'}, 'missing or undeclared source input')
	for name, pin in m['files'].items():
		require(selected(name) and not Path(name).is_absolute() and '..' not in Path(name).parts, 'source outside public closure')
		verify(ROOT/name, pin)
	for name in licenses:
		require(name in m['files'] and (ROOT/name).stat().st_size, 'missing license/provenance')
	return m


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--commit', required=True)
	p.add_argument('--output', required=True, type=Path)
	p.add_argument('--spec', default='packaging/rpm/astrac.spec')
	p.add_argument('--archive-only', action='store_true')
	p.add_argument('--rhel9-seed', type=Path, help='Use the pinned RHEL 9 LLVM 22 build-only seed')
	a = p.parse_args()
	require(Path(a.spec).resolve() == ROOT/'packaging/rpm/astrac.spec', 'wrong spec/package requested')
	a.spec = 'packaging/rpm/astrac.spec'
	output = external(a.output, fresh=False)
	top = output/('srpm-'+a.commit)
	top.mkdir()
	sources = top/'SOURCES'
	sources.mkdir()
	path, manifest = archive(a.commit, sources, a.rhel9_seed)
	pin, seed_path, licenses = seed_contract(manifest.get('target'))
	template = git('show', a.commit+':'+a.spec).decode()
	require(re.search(r'^Name:\s+astrac$', template, re.M), 'wrong package name')
	values = dict(COMMIT=a.commit, TREE=manifest['tree'], SHORT=a.commit[:12], DATE=datetime.datetime.fromtimestamp(manifest['epoch'], datetime.timezone.utc).strftime('%Y%m%d%H%M%S'), SOURCE_SHA=sha(path), RHEL9='1' if a.rhel9_seed else '0', SEED_SHA=pin['sha256'], SEED_NAME=Path(seed_path).name)
	for key, value in values.items():
		template = template.replace('@'+key+'@', value)
	spec = top/'astrac.spec'
	spec.write_text(template)
	write(top/'source-receipt.json', dict(commit=a.commit, tree=manifest['tree'], source_sha256=sha(path), seed=pin, licenses=list(licenses), manifest=manifest))
	if not a.archive_only:
		env = dict(os.environ, SOURCE_DATE_EPOCH=str(manifest['epoch']))
		for item in (spec, *sources.iterdir()):
			os.utime(item, (manifest['epoch'], manifest['epoch']))
			# RPM 6 stores an expanded spec in the SRPM header. Relative source/build
			# macros keep that header independent of the source builder's home path.
			# Only -bs uses these macros; --rebuild gets the original portable spec.
		subprocess.run(['rpmbuild', '-bs', '--target', 'x86_64', '--define', '_topdir '+str(top), '--define', '_srcrpmdir '+str(output), '--define', '_sourcedir .', '--define', '_builddir ./BUILD', '--define', '_buildhost astra-source.invalid', '--define', 'source_date_epoch_from_changelog 0', '--define', 'use_source_date_epoch_as_buildtime 1', '../astrac.spec'], check=True, env=env, cwd=sources)
		artifacts = list(output.glob('astrac-*.src.rpm'))
		require(len(artifacts) == 1, 'ambiguous source RPM output')
		subprocess.run(['rpm', '-qpl', artifacts[0]], check=True)
		write(top/'srpm-receipt.json', dict(commit=a.commit, source_sha256=sha(path), seed=pin, srpm=dict(name=artifacts[0].name, bytes=artifacts[0].stat().st_size, sha256=sha(artifacts[0]))))
	print('SOURCE_SNAPSHOT_CREATED', a.commit, sha(path))


if __name__ == '__main__':
	main()
