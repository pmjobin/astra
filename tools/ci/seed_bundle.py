#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind the retained seed to the authenticated report and create a local capsule."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import subprocess
import tarfile
import zipfile

from common import ROOT, external, identify, require, sha, verify, write
from trust import seed_manifest


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('report', 'seed', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	lock = seed_manifest(ROOT/'tools/ci/seed-linux.json')
	verify(a.seed, lock)
	require(sha(a.report) == lock['provenance']['report_sha256'], 'historical report identity mismatch')
	with zipfile.ZipFile(a.report) as report:
		manifest = json.loads(report.read('MANIFEST.json'))
		for row in manifest['files']:
			data = report.read(row['path'])
			require(len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256'], 'report member mismatch')
		transport = json.loads(report.read('evidence/transport.json'))
		parts = []
		for row in transport['segments']:
			data = report.read('evidence/'+row['path'])
			require(len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256'], 'report transport mismatch')
			parts.append(data)
		archive = b''.join(parts)
		require(hashlib.sha256(archive).hexdigest() == transport['archive_sha256'], 'transport archive mismatch')
	with tarfile.open(fileobj=io.BytesIO(archive)) as old:
		index = json.load(old.extractfile('INDEX.json'))
		rows = {}
		for name in ('payload/build/stage3/astrac-O2', 'payload/runtime/stage3/result.json'):
			row = index['files'][name]
			data = old.extractfile(row['blob']).read()
			require(len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256'], 'historical payload mismatch')
			rows[name] = row
			if name.endswith('astrac-O2'):
				require(data == a.seed.read_bytes(), 'live seed differs from reported binary')
			else:
				receipt = data
				require(row['sha256'] == lock['provenance']['stage_receipt_sha256'], 'stage receipt mismatch')
	build, runtime = external(a.build), external(a.runtime)
	commit = lock['source_commit']
	require(subprocess.check_output(['git', 'rev-parse', commit+'^{tree}'], cwd=ROOT, text=True).strip() == lock['source_tree'], 'historical source tree unavailable')
	sources = subprocess.check_output(['git', 'archive', '--format=tar', commit, 'compiler', 'lib', 'LICENSE.txt'], cwd=ROOT)
	# The generation recipe was committed with the report, after the frozen
	# compiler revision. Keep these two authentic revisions distinct.
	recipe = subprocess.check_output(['git', 'show', lock['provenance']['report_commit']+':tests/selfhost-convergence-27d/run.py'], cwd=ROOT)
	provenance = dict(format='astra-seed-capsule/1', status='LOCAL_AUTHENTICATED_NOT_PUBLISHED', seed=lock, report=identify(a.report), report_archive_sha256=transport['archive_sha256'], historical_payloads=rows, source_archive_sha256=hashlib.sha256(sources).hexdigest(), historical_recipe_commit=lock['provenance']['report_commit'], historical_recipe_sha256=hashlib.sha256(recipe).hexdigest(), recipe_sha256=sha(__file__), runtime='LLVM 23.1.4 is acquired separately from the pinned official archive; compile its C API shared library with llvm_dylib.py on the declared Linux distro. No host LLVM fallback.')
	files = {'astrac-seed':a.seed.read_bytes(), 'seed.json':(ROOT/'tools/ci/seed-linux.json').read_bytes(), 'LLVM.json':(ROOT/'tools/ci/llvm-linux.json').read_bytes(), 'LICENSE.txt':subprocess.check_output(['git', 'show', commit+':LICENSE.txt'], cwd=ROOT), 'stage3-result.json':receipt, 'source.tar':sources, 'historical-generation.py.txt':recipe, 'PROVENANCE.json':(json.dumps(provenance, sort_keys=True, indent=2)+'\n').encode()}
	for attempt in range(2):
		path = build/('astra-27d-seed-linux-x86_64'+('' if attempt == 0 else '-repeated')+'.tar.xz')
		with tarfile.open(path, 'w:xz', format=tarfile.USTAR_FORMAT) as capsule:
			for name, data in sorted(files.items()):
				info = tarfile.TarInfo(name)
				info.size = len(data)
				info.mode = 0o755 if name == 'astrac-seed' else 0o644
				info.mtime = 1794873600
				capsule.addfile(info, io.BytesIO(data))
	first, second = sorted(build.glob('*.tar.xz'))
	require(sha(first) == sha(second), 'seed capsule is not reproducible')
	write(runtime/'result.json', dict(**provenance, artifact=identify(build/'astra-27d-seed-linux-x86_64.tar.xz'), repeated_sha256=sha(second), members={name:dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest()) for name, data in files.items()}))
	print('LOCAL_SEED_REPORT_BINDING_AND_CAPSULE_REPRODUCTION_PASS')


if __name__ == '__main__':
	main()
