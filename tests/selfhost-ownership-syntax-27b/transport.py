#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Package reviewable 27-B evidence; only installed pm-next publishes the report."""
import argparse
import errno
import json
import os
from pathlib import Path
import shutil
import sys

from support import output_path, sha, write

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-compiler-complete'))
from evidence import pack, verify


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('audit', 'output'): p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	output = output_path(a.output, WORK/'runtime'); assert not output.exists(); output.mkdir()
	audit = json.loads((a.audit/'result.json').read_text())
	assert audit['status'] == 'BOUNDED_27B_IMPLEMENTATION_QUALIFIED_HISTORICAL_PRESERVATION_PARTIAL'
	selected = output/'selected'; selected.mkdir(); runtime = selected/'runtime'; runtime.mkdir(); build = selected/'build'; build.mkdir()
	omitted = []; selected_count = 0
	def retain(source, destination, reason=None):
		nonlocal selected_count
		if source.is_symlink():
			omitted.append(dict(path=str(source), symlink=os.readlink(source), reason=reason or 'Generated tool/build symlink; no source or proof byte substitution.')); return
		assert source.is_file()
		if reason:
			omitted.append(dict(path=str(source), bytes=source.stat().st_size, sha256=sha(source), reason=reason, local_file_preserved=True)); return
		destination.parent.mkdir(parents=True, exist_ok=True)
		try: os.link(source, destination)
		except OSError as error:
			if error.errno != errno.EXDEV: raise
			shutil.copy2(source, destination)
		selected_count += 1
	for group in sorted((WORK/'runtime').glob('selfhost27b*')):
		if not group.is_dir() or group.name.startswith('selfhost27b-report') or group == output: continue
		for source in sorted(group.rglob('*')):
			if source.is_dir() and not source.is_symlink(): continue
			name = str(source.relative_to(group)); reason = None
			if group.name == 'selfhost27b-recovery':
				if name.startswith(('blobs/', 'predecessor-transport.tar.xz')): reason = 'Redundant authenticated predecessor transport/blob; exact prior ZIP and recovery index retained locally and hash-bound.'
				elif name.startswith(('capsule/root/', 'formatter-tools/')) and not name.endswith('/result.json'): reason = 'Restored external tool distribution; exact tool/package hashes and recovery provenance retained; no host tool replacement.'
				elif name.endswith('.rpm'): reason = 'External recovery RPM; exact package hash and download provenance retained.'
				elif name.startswith('tmp/'): reason = 'Temporary compiler scratch; source, commands and durable products retained separately.'
			if name == 'predecessor-27a-report.zip': reason = 'Redundant 24,811,599-byte original report; exact original remains locally preserved and hash-bound.'
			retain(source, runtime/group.name/name, reason)
	for source in sorted((WORK/'build/selfhost27b').rglob('*')):
		if source.is_dir() and not source.is_symlink(): continue
		name = str(source.relative_to(WORK/'build/selfhost27b')); reason = None
		if name.startswith(('c0-recovery/', 'c0-recovery-safealloc2/')):
			# C0's debug ELF alone compresses beyond the installed 25 MiB ZIP cap.
			# Keep its exact local bytes and hash every omission. No stripped or
			# substituted compiler is presented as the qualified C0.
			if Path(name).name not in ('build.ninja', 'intro-buildoptions.json', 'meson-log.txt'):
				reason = 'C0 recovery debug binary/generated intermediate exceeds bounded report transport; exact live file preserved, hash-bound and rebuild commands retained. No substituted C0 product.'
		retain(source, build/name, reason)
	write(runtime/'transport-selection.json', dict(format='astra27b-explicit-evidence-selection/1', retained_files=selected_count, omissions=omitted, limitation='All listed omissions remain local; generated tool distributions, temporary scratch, redundant predecessor transport and oversized C0 debug/intermediate products are not claimed to be reconstructable from this report. Actual 27-B compiler products, current source snapshots, native products, failed attempts and receipts are transported.'))
	for name in ('pm-next-intake.json', 'pm-next-result.json'):
		source = WORK/'runtime/native-current'/name
		if source.is_file(): retain(source, runtime/'native-current'/name)
	archive = output/'task-evidence.tar.xz'
	packed = pack(['runtime='+str(runtime), 'build='+str(build)], archive, output)
	write(output/'pack.json', packed)
	verified = verify(archive, output); assert verified['status'] == 'BYTE_EXACT' and verified['archive_sha256'] == packed['archive_sha256']
	write(output/'reconstruction.json', verified)
	assert archive.stat().st_size < 22*1024**2, 'Keep exact attempt and resolve transport capacity without changing installed publisher.'
	attachments = output/'attachments'; attachments.mkdir(); segments = []
	with archive.open('rb') as stream:
		while data := stream.read(1700000):
			path = attachments/('transport-'+str(len(segments)).zfill(3)+'.indices'); path.write_bytes(data)
			segments.append(dict(path=path.name, bytes=len(data), sha256=sha(path)))
	write(attachments/'transport.json', dict(format='astra27b-evidence-transport/1', archive_bytes=archive.stat().st_size, archive_sha256=sha(archive), segments=segments, pack=packed, reconstruction=verified, omitted_local_files=len(omitted), selection_manifest_logical_path='runtime/transport-selection.json', explanation='Concatenate hash-checked segments, verify archive hash, then use the supplied unchanged content-addressed evidence decoder. Reconstruction grants no execution credit. Explicit generated/tool/C0 debug omissions remain local and hash-bound in the selection manifest.'))
	for name, path in [('engineering-audit.json', a.audit/'result.json'), ('preservation.json', a.audit/'preservation.json'), ('pack.json', output/'pack.json'), ('reconstruction.json', output/'reconstruction.json'), ('evidence-decoder.txt', ROOT/'tests/selfhost-compiler-complete/evidence.py'), ('columns-decoder.txt', ROOT/'tests/selfhost-compiler-complete/columns.py')]: shutil.copyfile(path, attachments/name)
	files = [dict(path=path.name, bytes=path.stat().st_size, sha256=sha(path)) for path in sorted(attachments.iterdir())]
	write(attachments/'manifest.json', dict(format='pm-next-evidence/1', files=files))
	print('BYTE_EXACT_SELECTED_27B_EVIDENCE_READY', archive.stat().st_size, attachments/'manifest.json', flush=True)


if __name__ == '__main__': main()
