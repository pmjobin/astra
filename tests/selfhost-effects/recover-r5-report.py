#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless R5 evidence and independent after-publication delivery verification."""
import argparse
import hashlib
import io
import json
import lzma
from pathlib import Path
import subprocess
import sys
import tarfile
import time
import zipfile
from state import ROOT, load_module, read, sha, git, bounded_run

PREVIOUS = 'c188a95de8b070ad5fd396afb2ad6d4132649278f05ba0e5dc49a1f3d9e8e00c'


def verify_archive(path):
	with tarfile.open(path, 'r|xz') as packed:
		observed = {}; index = None
		for member in packed:
			assert member.isfile() and not Path(member.name).is_absolute() and '..' not in Path(member.name).parts
			stream = packed.extractfile(member)
			if member.name == 'INDEX.json': index = json.load(stream); continue
			h = hashlib.sha256(); count = 0
			for block in iter(lambda: stream.read(1048576), b''): h.update(block); count += len(block)
			assert member.name == 'blobs/'+h.hexdigest() and member.name not in observed; observed[member.name] = (count, h.hexdigest())
	assert index['format'] == 'astra-effects25-evidence/3' and index['milestone'] == 'ASTRA-SELFHOST-EFFECTS-25-R5'
	assert set(observed) == {r['blob'] for r in index['files'].values() if 'blob' in r}
	for name, row in index['files'].items():
		assert not Path(name).is_absolute() and '..' not in Path(name).parts
		if 'blob' in row: assert observed[row['blob']] == (row['bytes'], row['sha256'])
		else: assert row['columns']['bytes'] == row['bytes'] and row['columns']['sha256'] == row['sha256']
	return index


def column_plan(paths, path, logical):
	columns = load_module('r5_transport_columns', ROOT/'tests/selfhost-genref/columns.py'); root = paths.RUNTIME/'handoff-columns'; root.mkdir(exist_ok=True); key = sha(path); receipt = root/(key+'.json')
	if receipt.exists(): plan = read(receipt)
	else:
		plan = columns.encode(path, root, logical, key[:20]); receipt.write_text(json.dumps(plan, indent=2)+'\n')
	assert plan['bytes'] == path.stat().st_size and plan['sha256'] == key
	h = hashlib.sha256(); count = 0
	for block in columns.reconstruct(root, plan): h.update(block); count += len(block)
	assert h.hexdigest() == key and count == path.stat().st_size
	return root, plan


def restore_all(archive, leaf, expected):
	# Independent unchanged decoder reconstructs every logical original byte,
	# including column-encoded observations, before any publication claim.
	argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/restore.py', archive, '--output', leaf/'decoded', '--verify-only']; r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/'restore.time', *argv], capture_output=True, timeout=1200); (leaf/'restore.stdout').write_bytes(r.stdout); (leaf/'restore.stderr').write_bytes(r.stderr); assert r.returncode == 0, r.stderr[-2500:]; result = json.loads(r.stdout); assert result['status'] == 'BYTE_EXACT' and result['logical_files'] == expected


def pack(paths, a):
	assert not git('status', '--porcelain=v1', '--untracked-files=all').strip(); audit = read(a.audit); assert audit['status'] == 'PARTIAL' and (audit['final_commit'], audit['final_tree']) == (git('rev-parse', 'HEAD').strip(), git('rev-parse', 'HEAD^{tree}').strip())
	leaf = paths.RUNTIME/('handoff-'+a.version); leaf.mkdir(); archive = leaf/'effects25-r5-evidence.tar.xz'; files = {}; blobs = set(); external = {}; start = time.monotonic(); encoded = {}
	excluded = {'predecessor-report.zip', 'r4-report-evidence', 'r4-evidence.tar.xz', 'r4-evidence-index.json'}
	# These are byte-identical transport copies from the authenticated immutable
	# predecessor, not new runs. Keep their hashes and selection receipts, and
	# retain every selected source/receipt actually used under r4-history/.
	for name in excluded:
		path = paths.RUNTIME/name
		if path.is_file(): external[name] = dict(bytes=path.stat().st_size, sha256=sha(path), provenance='Redundant predecessor transport copy; exact predecessor ZIP remains preserved in runtime')
	with lzma.LZMAFile(archive, 'wb', filters=[dict(id=lzma.FILTER_LZMA2, preset=9, dict_size=64*1024**2)]) as compressed, tarfile.open(fileobj=compressed, mode='w|') as packed:
		def store(name, stream, size):
			entry = tarfile.TarInfo(name); entry.mode = 0o644; entry.size = size; packed.addfile(entry, stream)
		def add(name, path, transform=True):
			digest = sha(path); size = path.stat().st_size; row = dict(bytes=size, sha256=digest, mode=oct(path.stat().st_mode & 0o777), blob='blobs/'+digest)
			if name in files: assert files[name]['sha256'] == digest; return
			if transform and path.suffix == '.stdout' and size >= 1048576:
				with path.open('rb') as stream: first = stream.readline()
				if not first.startswith(b'('):
					if digest not in encoded: encoded[digest] = column_plan(paths, path, name)
					root, plan = encoded[digest]
					for part in list(plan['parts'].values())+[p for group in plan['groups'] for p in group['columns']]: add('columns/'+part['path'], root/part['path'], False)
					row.pop('blob'); row['columns'] = dict(plan, path=name); files[name] = row; return
			files[name] = row
			if digest not in blobs:
				with path.open('rb') as stream: store('blobs/'+digest, stream, size)
				blobs.add(digest)
		for prefix, root in [('runtime', paths.RUNTIME), ('build', paths.BUILD)]:
			for path in sorted(root.rglob('*')):
				if not path.is_file(): continue
				assert not path.is_symlink(); relative = path.relative_to(root)
				if prefix == 'runtime' and (relative.parts[0] in excluded or relative.parts[0].startswith(('handoff-', 'published-verification-'))): continue
				add(prefix+'/'+str(relative), path)
		index = dict(format='astra-effects25-evidence/3', milestone='ASTRA-SELFHOST-EFFECTS-25-R5', final_commit=audit['final_commit'], final_tree=audit['final_tree'], files=files, predecessor_transport=external, previous_report_sha256=PREVIOUS, limitation='All R5 source/build/runtime evidence, including failed/partial receipts and actual compiler products, is retained. Large tabular stdout uses the unchanged independently verified lossless column transport. Only duplicate predecessor decoding/transport copies and this packaging output are excluded; original checkpoints remain immutable and separately identified.')
		data = (json.dumps(index, indent=2)+'\n').encode(); store('INDEX.json', io.BytesIO(data), len(data))
	assert verify_archive(archive) == index
	restore_all(archive, leaf, len(files))
	attachments = leaf/'attachments'; tool = ROOT/'tools/qualification/encoded-evidence.py'; r = bounded_run([sys.executable, '-B', tool, 'pack', '--input', archive, '--output', attachments, '--stem', 'effects25-r5'], capture_output=True, timeout=300); (leaf/'encoding.stdout').write_bytes(r.stdout); (leaf/'encoding.stderr').write_bytes(r.stderr); assert r.returncode == 0, r.stderr[-2000:]
	(attachments/'final-audit.json').write_bytes(a.audit.read_bytes()); (attachments/'decode-evidence.py.txt').write_bytes(tool.read_bytes()); (attachments/'verify-evidence.py.txt').write_bytes(Path(__file__).read_bytes()); (attachments/'restore-effects.py.txt').write_bytes((ROOT/'tests/selfhost-effects/restore.py').read_bytes()); (attachments/'restore-columns.py.txt').write_bytes((ROOT/'tests/selfhost-genref/columns.py').read_bytes())
	packaging = dict(status='LOSSLESS_R5_EVIDENCE_VERIFIED', logical_files=len(files), unique_blobs=len(blobs), archive_bytes=archive.stat().st_size, archive_sha256=sha(archive), seconds=time.monotonic()-start, previous_report_sha256=PREVIOUS, xz_dictionary_bytes=64*1024**2, G12='PENDING actual installed publication and separate delivered-ZIP verification')
	(attachments/'packaging.json').write_text(json.dumps(packaging, indent=2)+'\n'); (attachments/'review-guide.txt').write_text('Read final-audit.json. Decode effects25-r5-encoding.json with decode-evidence.py.txt. The tar.xz stores content-addressed blobs, lossless token columns and INDEX.json; every logical file maps to its exact SHA-256, size and original mode. Save restore-effects.py.txt and restore-columns.py.txt together as restore-effects.py and restore-columns.py, then run python3 restore-effects.py ARCHIVE --output DIRECTORY --verify-only to reconstruct and verify every logical byte without executing evidence. The committed recover-r5-report.py verify mode checks the actual delivered ZIP, source/Git bindings and every archive byte. Overall status is PARTIAL; original unchanged flow_number has ZERO Astra executions. Source witnesses were never copied over the live checkout. Predecessor transport copies are identified by hash, with used source/receipt witnesses retained in r4-history.\n')
	rows = [dict(path=p.name, bytes=p.stat().st_size, sha256=sha(p)) for p in sorted(attachments.iterdir())]; assert len(rows) <= 128 and all(r['bytes'] <= 2*1024**2 for r in rows); manifest = attachments/'INDEX.json'; manifest.write_text(json.dumps(dict(format='pm-next-evidence/1', files=rows), indent=2)+'\n')
	descriptor = dict(status='PARTIAL', summary='ASTRA-SELFHOST-EFFECTS-25-R5 qualifies source-bound exact-width unary boolean !, integer +/~ and signed integer - on recorded typed operands through original source, independent Flow/Core/CFG/SSA/LLVM boundaries and matched O0/O2 native execution. Each profile freshly retains 340 R4 program identities (74 real error paths), 101 semantic/52 LLVM-valid physical categories, and executes 13 new programs including eight real errors with independent C0 and unsuppressed returning Valgrind. Original C0 oracles and four frozen source/node cohorts remain independently attributed. Strict raw LLVM/ELF drift, including relocation-dependent generic identities and historical R4-vs-R3 0/120 effects raw identity, is disclosed without normalization claims. Mandatory original execution remains unproved: '+audit['remaining_boundary']+' This is PARTIAL for the unchanged entire milestone-25 contract; no R4 retroactive PASS, narrowed success, Stage1, milestone26, release or push.', tests=[key+': '+value for key, value in audit['gates'].items()]+['All cold/warm/failed checks and unsuppressed memory traces are preserved in lossless indexed evidence. Warm identity reuse is not recompilation or speedup.','Publication gate G12 is pending until the installed publisher runs and the delivered ZIP is independently verified afterward.'])
	(paths.RUNTIME.parent/'native-current/pm-next-result.json').write_text(json.dumps(descriptor, indent=2)+'\n'); print('EVIDENCE_MANIFEST', manifest, flush=True); print(json.dumps(packaging), flush=True)


def verify(paths, a):
	assert not git('status', '--porcelain=v1', '--untracked-files=all').strip(); report = ROOT.parent/'codex/reports/astra-report-current.zip'; assert report.stat().st_size <= 25*1024**2 and sha(paths.RUNTIME/'predecessor-report.zip') == PREVIOUS
	leaf = paths.RUNTIME/('published-verification-'+a.version); leaf.mkdir()
	with zipfile.ZipFile(report) as archive:
		names = archive.namelist(); assert len(names) == len(set(names)) and archive.testzip() is None; manifest = json.loads(archive.read('MANIFEST.json')); assert set(names) == {'MANIFEST.json'} | {r['path'] for r in manifest['files']}
		for row in manifest['files']:
			data = archive.read(row['path']); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		result = json.loads(archive.read('RESULT.json')); assert result['status'] == 'PARTIAL' and result['milestone_id'] == 'ASTRA-SELFHOST-EFFECTS-25-R5' and result['submission_sha256'] == 'e7837fba03f7a19c6552776488d5848849cc65b50f3b46eb3d505c4ce4b51541' and result['start_commit'] == 'c271e0822d0fc12a878a5adc1388aa1a8e147067' and not result['final_dirty_tracked_paths'] and not result['untracked_inventory_changed']
		assert (result['final_commit'], result['final_tree']) == (git('rev-parse', 'HEAD').strip(), git('rev-parse', 'HEAD^{tree}').strip()) and subprocess.run(['git', 'merge-base', '--is-ancestor', result['start_commit'], result['final_commit']], cwd=ROOT).returncode == 0
		assert 'OMISSIONS.md' not in names
		assert {name[7:] for name in names if name.startswith('source/')} == set(result['changed_committed_paths'])
		for name in names:
			if name.startswith('source/'): assert archive.read(name) == subprocess.check_output(['git', 'show', result['final_commit']+':'+name[7:]], cwd=ROOT)
		assert json.loads(archive.read('evidence/final-audit.json')) == read(a.audit)
		for name in names:
			if name.startswith('evidence/'):
				relative = Path(name[9:]); assert len(relative.parts) == 1; (leaf/relative).write_bytes(archive.read(name))
	decoder = load_module('r5_delivered_decoder', ROOT/'tools/qualification/encoded-evidence.py'); model, data = decoder.decode(leaf/'effects25-r5-encoding.json'); packaging = read(leaf/'packaging.json'); assert len(data) == packaging['archive_bytes'] and hashlib.sha256(data).hexdigest() == packaging['archive_sha256']; path = leaf/'effects25-r5-evidence.tar.xz'; path.write_bytes(data); index = verify_archive(path)
	assert len(index['files']) == packaging['logical_files'] and (index['final_commit'], index['final_tree']) == (result['final_commit'], result['final_tree']); restore_all(path, leaf, len(index['files']))
	intake = read(paths.RUNTIME.parent/'native-current/pm-next-intake.json'); assert intake['published'] and intake['report_sha256'] == sha(report) and (intake['final_commit'], intake['final_tree']) == (result['final_commit'], result['final_tree'])
	receipt = dict(status='PUBLISHED_R5_PARTIAL_VERIFIED', G12='PASS: installed publisher plus independent after-delivery ZIP/member/source/Git/transport verification', report=str(report), report_bytes=report.stat().st_size, report_sha256=sha(report), final_commit=result['final_commit'], final_tree=result['final_tree'], payloads=len(manifest['files']), logical_evidence_files=len(index['files']), evidence_archive_sha256=sha(path), previous_report_sha256=PREVIOUS, original_flow_number_Astra_executions=dict(O0=0, O2=0), limitation='G12 establishes delivery integrity only. Unfinished source/owner/effects gates and overall milestone remain PARTIAL.')
	(paths.RUNTIME/('published-verification-'+a.version+'.json')).write_text(json.dumps(receipt, indent=2)+'\n'); print(json.dumps(receipt, indent=2), flush=True)


def main():
	p = argparse.ArgumentParser(); p.add_argument('mode', choices=('pack', 'verify', 'prepare')); p.add_argument('--version', required=True); p.add_argument('--audit', type=Path); a = p.parse_args(); assert a.version.isalnum(); paths = load_module('r5_report_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	if a.mode == 'prepare':
		seen = set()
		for path in sorted(paths.RUNTIME.rglob('*.stdout')):
			if path.stat().st_size < 1048576 or path.relative_to(paths.RUNTIME).parts[0].startswith(('r4-history', 'r4-report-evidence', 'handoff-', 'published-verification-')): continue
			with path.open('rb') as stream: first = stream.readline()
			key = sha(path)
			if key not in seen and not first.startswith(b'('): column_plan(paths, path, 'runtime/'+str(path.relative_to(paths.RUNTIME))); seen.add(key); print('Verified lossless transport', len(seen), path.name, flush=True)
		return
	assert a.audit and a.audit.is_file()
	if a.mode == 'pack': pack(paths, a)
	else: verify(paths, a)


if __name__ == '__main__':
	main()
