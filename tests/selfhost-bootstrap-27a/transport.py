#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Package exact task evidence with the existing lossless evidence transport.

Old delivered ZIP/transport duplicates stay preserved locally and hash-bound by
G0; only their redundant binary copies and temporary compiler scratch are left
out. All new attempts, products and failed/stopped receipts are retained.
The installed publisher alone creates the canonical report.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-compiler-complete'))
from run import WORK, sha
from acceleration import output_path, write
from evidence import pack, verify


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for n in ('runtime', 'build', 'output', 'audit'): p.add_argument('--'+n, type=Path, required=True)
	a = p.parse_args()
	output_path(a.runtime, WORK/'runtime'); output_path(a.build, WORK/'build'); output_path(a.output, WORK/'runtime')
	assert not a.output.exists() and not a.output.is_relative_to(a.runtime) and not a.output.is_relative_to(a.build)
	a.output.mkdir(); staged = a.output/'selected-runtime'; staged.mkdir()
	assert json.loads((a.audit/'result.json').read_text())['status'] == 'BOUNDED_27A_ENGINEERING_PASS'
	excluded = {'G0/predecessor-delivered-report.zip', 'G0/delivered-evidence.tar.xz'}
	omissions = []
	for source in sorted(a.runtime.rglob('*')):
		name = str(source.relative_to(a.runtime))
		if name == 'tmp' or name.startswith('tmp/') or name in excluded:
			if source.is_file(): omissions.append(dict(path=name, bytes=source.stat().st_size, sha256=sha(source), reason='Temporary compiler scratch' if name.startswith('tmp/') else 'Redundant predecessor binary; immutable local copy retained and G0 authenticated.'))
			continue
		assert not source.is_symlink(), source
		if source.is_dir(): continue
		assert source.is_file()
		destination = staged/name; destination.parent.mkdir(parents=True, exist_ok=True)
		os.link(source, destination)
	archive = a.output/'task-evidence.tar.xz'
	result = pack(['runtime='+str(staged), 'build='+str(a.build)], archive, a.output)
	verified = verify(archive, a.output)
	assert verified['status'] == 'BYTE_EXACT' and verified['archive_sha256'] == result['archive_sha256']
	write(a.output/'pack.json', result); write(a.output/'reconstruction.json', verified)
	# Leave room below the installed publisher's 25 MiB final ZIP limit.
	assert archive.stat().st_size < 23*1024**2, result
	attachments = a.output/'attachments'; attachments.mkdir()
	segments = []
	with archive.open('rb') as stream:
		while block := stream.read(1700000):
			path = attachments/('transport-'+str(len(segments)).zfill(3)+'.indices'); path.write_bytes(block)
			segments.append(dict(path=path.name, bytes=len(block), sha256=sha(path)))
	transport = dict(format='astra-27a-lossless-transport/1', archive_bytes=archive.stat().st_size, archive_sha256=sha(archive), segments=segments, pack=result, reconstruction=verified, exclusions=omissions, explanation='Concatenate segments in order, verify their hashes and the archive hash, then use the supplied byte-exact tracked evidence/columns decoder. Decoding grants no execution credit. The old delivered predecessor and its transport remain locally preserved; G0 binds their exact identities.')
	write(attachments/'transport.json', transport)
	for name, source in [('engineering-audit.json', a.audit/'result.json'), ('pack.json', a.output/'pack.json'), ('reconstruction.json', a.output/'reconstruction.json'), ('evidence-decoder.txt', ROOT/'tests/selfhost-compiler-complete/evidence.py'), ('columns-decoder.txt', ROOT/'tests/selfhost-compiler-complete/columns.py')]:
		shutil.copyfile(source, attachments/name)
	files = [dict(path=p.name, bytes=p.stat().st_size, sha256=sha(p)) for p in sorted(attachments.iterdir())]
	write(attachments/'manifest.json', dict(format='pm-next-evidence/1', files=files))
	print('BYTE_EXACT_27A_EVIDENCE_READY', archive.stat().st_size, attachments/'manifest.json', flush=True)


if __name__ == '__main__':
	main()
