#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless continuation transport; only installed pm-next publishes the ZIP."""
import argparse
import hashlib
import io
import json
import lzma
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import time
import zipfile
from state import ROOT, load_module, read, sha, git, bounded_run

PREVIOUS = '16408c8bd00c3e81633e2ab7cefa6d557bbdad0dbdd9239add328c160fe7f887'
SUBMISSION = 'e7837fba03f7a19c6552776488d5848849cc65b50f3b46eb3d505c4ce4b51541'
BASE = 'c271e0822d0fc12a878a5adc1388aa1a8e147067'


def verified_zip(path, expected=None):
	if expected:
		assert sha(path) == expected
	with zipfile.ZipFile(path) as archive:
		names = archive.namelist()
		assert len(names) == len(set(names)) and archive.testzip() is None
		manifest = json.loads(archive.read('MANIFEST.json'))
		assert set(names) == {'MANIFEST.json'} | {row['path'] for row in manifest['files']}
		for row in manifest['files']:
			data = archive.read(row['path'])
			assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		result = json.loads(archive.read('RESULT.json'))
		assert result['project_id'] == 'astra' and result['milestone_id'] == 'ASTRA-SELFHOST-EFFECTS-25-R5' and result['submission_sha256'] == SUBMISSION and result['start_commit'] == BASE
		return result, manifest


def prior_transport(paths, report):
	result, _ = verified_zip(report, PREVIOUS)
	assert result['status'] == 'PARTIAL' and result['final_commit'] == '0ce000667dd5cbee3e2af9fe0237b9c88a5536f3'
	with zipfile.ZipFile(report) as archive:
		packaging = json.loads(archive.read('evidence/packaging.json'))
	path = paths.RUNTIME.parent/'effects25-r5/handoff-transport/effects25-r5-evidence.tar.xz'
	assert path.stat().st_size == packaging['archive_bytes'] and sha(path) == packaging['archive_sha256']
	return path


def pack(paths, a, helpers):
	if a.digit_columns: assert a.content_chunks
	assert not git('status', '--porcelain=v1', '--untracked-files=all').strip()
	audit = read(a.audit)
	assert audit['format'] == 'astra-effects25-r5-continuation-audit/1' and audit['status'] in ('PASS', 'PARTIAL')
	assert (audit['final_commit'], audit['final_tree']) == (git('rev-parse', 'HEAD').strip(), git('rev-parse', 'HEAD^{tree}').strip())
	assert audit['previous_report_sha256'] == PREVIOUS and audit['gates']['G12'].startswith('PENDING')
	if audit['status'] == 'PASS':
		assert all(audit['gates']['G'+str(gate)].startswith('PASS') for gate in range(12))
	leaf = paths.RUNTIME/('handoff-'+a.version)
	leaf.mkdir()
	previous = prior_transport(paths, ROOT.parent/'codex/reports/astra-report-current.zip')
	old = helpers.verify_archive(previous)
	assert old['final_commit'] == '0ce000667dd5cbee3e2af9fe0237b9c88a5536f3'
	seed = helpers.verify_archive(a.seed_archive) if a.seed_archive else old
	assert all(seed['files'][name] == row for name, row in old['files'].items())
	if a.seed_archive: assert seed['previous_report_sha256'] == PREVIOUS
	assert subprocess.run(['git', 'merge-base', '--is-ancestor', seed['final_commit'], audit['final_commit']], cwd=ROOT).returncode == 0
	files, blobs, encoded = dict(seed['files']), set(), {}
	spool = leaf/'blob-spool'; spool.mkdir()
	pending, capture_generations, digit_cache = {}, [], {}
	byte_codec = load_module('resume_byte_codec', ROOT/'tests/selfhost-effects/transport-chunks.py') if a.digit_columns or a.content_chunks else None
	archive = leaf/'effects25-r5-resume-evidence.tar.xz'
	start = time.monotonic()
	with lzma.LZMAFile(archive, 'wb', filters=[dict(id=lzma.FILTER_LZMA2, preset=9, dict_size=a.dictionary_mib*1024**2)]) as compressed, tarfile.open(fileobj=compressed, mode='w|') as packed:
		def store(name, stream, size):
			# Physical ordering is independent of logical names and byte hashes.
			# Spooling permits similar captured compiler/Core variants to remain
			# adjacent in the larger bounded compression window, across history.
			assert name not in pending
			target = spool/Path(name).name
			with target.open('xb') as out: shutil.copyfileobj(stream, out, 1048576)
			assert target.stat().st_size == size
			pending[name] = target
		with tarfile.open(a.seed_archive or previous, 'r|xz') as inherited:
			for member in inherited:
				if member.name == 'INDEX.json':
					assert json.load(inherited.extractfile(member)) == seed
					continue
				assert member.isfile() and member.name.startswith('blobs/') and member.name not in blobs
				store(member.name, inherited.extractfile(member), member.size)
				blobs.add(member.name)
		def add_bytes(name, data, mode='0o644'):
			digest = hashlib.sha256(data).hexdigest(); blob = 'blobs/'+digest
			if name in files:
				assert files[name]['sha256'] == digest and files[name]['bytes'] == len(data)
				return
			files[name] = dict(bytes=len(data), sha256=digest, mode=mode, blob=blob)
			if blob not in blobs:
				store(blob, io.BytesIO(data), len(data)); blobs.add(blob)
		def add(name, path, transform=True):
			assert path.is_file() and not path.is_symlink()
			digest, size = sha(path), path.stat().st_size
			if a.digit_columns and name.startswith('resume/runtime/') and path.suffix == '.stdout' and size >= 1048576:
				with path.open('rb') as stream: first = stream.read(1)
				if first == b'(':
					if digest not in digit_cache:
						root = leaf/'digit-columns'; plan = byte_codec.digit_columns(path, root, name)
						columns = load_module('resume_original_column_decoder', ROOT/'tests/selfhost-genref/columns.py'); observed, count = hashlib.sha256(), 0
						for block in columns.reconstruct(root, plan): observed.update(block); count += len(block)
						assert observed.hexdigest() == digest and count == size
						digit_cache[digest] = root, plan
					root, plan = digit_cache[digest]
					for part in list(plan['parts'].values())+[part for group in plan['groups'] for part in group['columns']]: add('columns/'+part['path'], root/part['path'], False)
					if name in files: assert files[name]['sha256'] == digest and files[name]['bytes'] == size
					files[name] = dict(bytes=size, sha256=digest, mode=oct(path.stat().st_mode & 0o777), columns=dict(plan, path=name))
					return
			if name in files:
				if files[name]['sha256'] == digest and files[name]['bytes'] == size: return
				assert name.startswith('resume/runtime/pack-') and path.suffix in ('.stdout', '.stderr', '.time'), name
				generation = 'history/capture-generations/'+digest+'/'+name
				capture_generations.append(dict(logical_path=name, later_capture=generation, earlier_sha256=files[name]['sha256'], later_sha256=digest))
				add(generation, path, transform)
				return
			row = dict(bytes=size, sha256=digest, mode=oct(path.stat().st_mode & 0o777), blob='blobs/'+digest)
			if transform and path.suffix == '.stdout' and size >= 1048576:
				with path.open('rb') as stream: first = stream.readline()
				if not first.startswith(b'('):
					if digest not in encoded: encoded[digest] = helpers.column_plan(paths, path, name)
					root, plan = encoded[digest]
					for part in list(plan['parts'].values())+[part for group in plan['groups'] for part in group['columns']]: add('columns/'+part['path'], root/part['path'], False)
					row.pop('blob'); row['columns'] = dict(plan, path=name); files[name] = row
					return
			files[name] = row
			if row['blob'] not in blobs:
				with path.open('rb') as stream: store(row['blob'], stream, size)
				blobs.add(row['blob'])
		for prefix, root in [('runtime', paths.RUNTIME), ('build', paths.BUILD)]:
			for path in sorted(root.rglob('*')):
				if not path.is_file(): continue
				relative = path.relative_to(root)
				if prefix == 'runtime' and relative.parts[0].startswith(('handoff-', 'published-verification-')): continue
				add('resume/'+prefix+'/'+str(relative), path)
				# Adjacent original/current indexes share the bounded XZ window while
				# retaining the previous index's exact bytes and row ordering.
		with tarfile.open(previous, 'r:xz') as inherited: raw_index = inherited.extractfile('INDEX.json').read()
		add_bytes('history/previous-evidence-index.json', raw_index)
		index = dict(format='astra-effects25-evidence/3', milestone='ASTRA-SELFHOST-EFFECTS-25-R5', final_commit=audit['final_commit'], final_tree=audit['final_tree'], files=files, previous_report_sha256=PREVIOUS, previous_archive_sha256=sha(previous), previous_logical_files=len(old['files']), external_system_dependencies=old['external_system_dependencies'], predecessor_transport=old['predecessor_transport'], limitation='Every previous logical evidence row and blob is retained byte-exact. All continuation task products, source witnesses and failed/stopped/successful receipts are included under resume/. Packaging outputs and redundant prior ZIP transports are identified separately and remain preserved locally. Lossless token columns are independently reconstructed; source snapshots are witnesses, never copied over the checkout.')
		index['capture_generations'] = capture_generations
		if a.seed_archive:
			index['transport_seed'] = dict(path=str(a.seed_archive), bytes=a.seed_archive.stat().st_size, sha256=sha(a.seed_archive), logical_files=len(seed['files']), limitation='Verified oversize lossless transport retained locally. Every original logical path, byte count, byte hash and reconstructed file byte is preserved. Reversible byte encodings and physical order may change; all canonical predecessor rows remain exact. Packaging streams that completed after the seed capture have explicit additional generations.')
		if a.content_chunks:
			codec = byte_codec
			required = {row['blob'] for row in files.values() if 'blob' in row}; assert required <= set(pending)
			pending = {name: path for name, path in pending.items() if name in required}
			pool, storage, codec_receipt = codec.encode(pending, leaf, paths.BUILD/('transport-chunks-'+a.version))
			index.update(format='astra-effects25-evidence/4', storage=storage, chunk_codec_receipt=codec_receipt)
			pending = {storage['pool_blob']: pool}
		data = (json.dumps(index, indent=2)+'\n').encode(); store('INDEX.json', io.BytesIO(data), len(data))
		nominal = {}
		for name, row in files.items():
			if 'blob' in row: nominal.setdefault(row['blob'], name)
		column_order = {}
		for row in files.values():
			if 'columns' not in row: continue
			plan = row['columns']
			for kind, part in plan['parts'].items():
				blob = files['columns/'+part['path']]['blob']; key = (kind, '', 0, 0, part['bytes'])
				column_order[blob] = min(column_order.get(blob, key), key)
			for group in plan['groups']:
				for ordinal, part in enumerate(group['columns']):
					blob = files['columns/'+part['path']]['blob']; key = ('values', group['header'], int(group['raw']), ordinal, part['bytes'])
					column_order[blob] = min(column_order.get(blob, key), key)
		def order(name):
			if name == 'INDEX.json': return (9, '', 0, name)
			if a.content_chunks: return (0, '', 0, name)
			logical = nominal[name]; path = pending[name]; size = path.stat().st_size
			if logical == 'history/previous-evidence-index.json': return (8, '', 0, name)
			with path.open('rb') as stream: first = stream.read(128)
			base = Path(logical).name
			if first.startswith(b'\x7fELF'): return (0, 'large' if size >= 500000 else 'small', size, name)
			if first.startswith(b'('): return (1, base, size, name)
			if b'; ModuleID' in first or first.startswith(b'source_filename'): return (2, base, size, name)
			if first.lstrip().startswith((b'{', b'[')): return (3, base, size, name)
			if name in column_order: return (5, column_order[name], size, name)
			return (4, base, size, name)
		for name in sorted(pending, key=order):
			path = pending[name]; entry = tarfile.TarInfo(name); entry.mode = 0o644; entry.size = path.stat().st_size
			with path.open('rb') as stream: packed.addfile(entry, stream)
	standard_archive = archive
	if a.content_chunks:
		standard_archive = leaf/'reconstructed-standard.tar.xz'
		assert codec.decode(archive, standard_archive, index) == index
		standard = dict(index); standard['format'] = 'astra-effects25-evidence/3'; standard.pop('storage')
		assert helpers.verify_archive(standard_archive) == standard
	else: assert helpers.verify_archive(archive) == index
	assert all(index['files'][name] == row for name, row in old['files'].items())
	helpers.restore_all(standard_archive, leaf, len(files))
	attachments = leaf/'attachments'
	tool = ROOT/'tools/qualification/encoded-evidence.py'
	r = bounded_run([sys.executable, '-B', tool, 'pack', '--input', archive, '--output', attachments, '--stem', 'effects25-r5-resume'], capture_output=True, timeout=300)
	(leaf/'encoding.stdout').write_bytes(r.stdout); (leaf/'encoding.stderr').write_bytes(r.stderr)
	assert r.returncode == 0, r.stderr[-2000:]
	for name, path in [('final-audit.json', a.audit), ('decode-evidence.py.txt', tool), ('verify-evidence.py.txt', Path(__file__)), ('restore-effects.py.txt', ROOT/'tests/selfhost-effects/restore.py'), ('restore-columns.py.txt', ROOT/'tests/selfhost-genref/columns.py')]:
		(attachments/name).write_bytes(path.read_bytes())
	if a.content_chunks:
		(attachments/'restore-chunks.py.txt').write_bytes((ROOT/'tests/selfhost-effects/transport-chunks.py').read_bytes())
		(attachments/'chunk-codec-receipt.json').write_bytes((leaf/'chunk-codec-receipt.json').read_bytes())
	packaging = dict(status='LOSSLESS_R5_CONTINUATION_EVIDENCE_VERIFIED', logical_files=len(files), previous_logical_files=len(old['files']), unique_blobs=len(blobs), archive_bytes=archive.stat().st_size, archive_sha256=sha(archive), previous_report_sha256=PREVIOUS, previous_archive_sha256=sha(previous), seconds=time.monotonic()-start, G12='PENDING actual installed publication and independent after-delivery verification')
	packaging.update(dictionary_MiB=a.dictionary_mib, physical_order='similar ELF/Core/LLVM/JSON/column variants adjacent; original index adjacent to current index', transport_seed=index.get('transport_seed'))
	if a.content_chunks: packaging.update(storage_codec='content-defined byte chunks; lexicographically sorted pool', physical_order='lexicographically sorted distinct byte chunks; canonical predecessor rows unchanged', physical_blobs=1, unique_blobs=len(storage['blobs']), original_unique_blobs=len(storage['blobs']), unique_chunks=len(storage['chunks']), continued_Core_byte_encodings=len(digit_cache))
	(attachments/'packaging.json').write_text(json.dumps(packaging, indent=2)+'\n')
	(attachments/'review-guide.txt').write_text('Read final-audit.json for exact qualification and unproved gates. Decode effects25-r5-resume-encoding.json with decode-evidence.py.txt. The content-addressed archive retains every previous logical file and all continuation source/run/build receipts, including failures. Save restore-effects.py.txt and restore-columns.py.txt together as restore-effects.py and restore-columns.py, then run python3 restore-effects.py ARCHIVE --output DIRECTORY --verify-only. The independent decoder reconstructs and hashes every original byte without executing evidence. Historical observations remain tied to their captured compiler revisions; actual original full-population execution and reduced-view execution are separate. The installed publisher alone creates the canonical ZIP; G12 is checked only afterward.\n')
	if a.content_chunks:
		with (attachments/'review-guide.txt').open('a') as out: out.write('This v4 transport stores common byte chunks once. Before the unchanged original logical-file decoder, save restore-chunks.py.txt as restore-chunks.py and run python3 restore-chunks.py ARCHIVE --output reconstructed-standard.tar.xz. This independently hashes every reconstructed original blob and emits a standard v3 archive. Use that reconstructed standard archive with restore-effects.py. No evidence byte, original logical path or proof result is removed; encoder native-helper credit is zero.\n')
	rows = [dict(path=path.name, bytes=path.stat().st_size, sha256=sha(path)) for path in sorted(attachments.iterdir())]
	assert len(rows) <= 128 and all(row['bytes'] <= 2*1024**2 for row in rows)
	manifest = attachments/'INDEX.json'; manifest.write_text(json.dumps(dict(format='pm-next-evidence/1', files=rows), indent=2)+'\n')
	descriptor = dict(status=audit['status'], summary=audit['summary'], tests=[name+': '+value for name, value in audit['gates'].items()]+['All previous and continuation failed, stopped, cold and warm receipts are retained losslessly. Actual CPU/wall/RSS and overlapping intervals are independently attributed.','Publication G12 remains pending until the installed publisher and separate after-delivery check complete.'])
	(paths.RUNTIME.parent/'native-current/pm-next-result.json').write_text(json.dumps(descriptor, indent=2)+'\n')
	print('EVIDENCE_MANIFEST', manifest, flush=True)
	print(json.dumps(packaging), flush=True)


def verify(paths, a, helpers):
	assert not git('status', '--porcelain=v1', '--untracked-files=all').strip()
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert report.stat().st_size <= 25*1024**2
	result, manifest = verified_zip(report)
	audit = read(a.audit)
	assert result['status'] == audit['status'] and (result['final_commit'], result['final_tree']) == (audit['final_commit'], audit['final_tree']) == (git('rev-parse', 'HEAD').strip(), git('rev-parse', 'HEAD^{tree}').strip())
	assert not result['final_dirty_tracked_paths'] and not result['untracked_inventory_changed']
	assert result['amendment']['previous_report_sha256'] == PREVIOUS
	assert subprocess.run(['git', 'merge-base', '--is-ancestor', BASE, result['final_commit']], cwd=ROOT).returncode == 0
	leaf = paths.RUNTIME/('published-verification-'+a.version); leaf.mkdir()
	with zipfile.ZipFile(report) as archive:
		assert 'OMISSIONS.md' not in archive.namelist()
		assert {name[7:] for name in archive.namelist() if name.startswith('source/')} == set(result['changed_committed_paths'])
		for name in archive.namelist():
			if name.startswith('source/'):
				assert archive.read(name) == subprocess.check_output(['git', 'show', result['final_commit']+':'+name[7:]], cwd=ROOT)
			if name.startswith('evidence/'):
				relative = Path(name[9:]); assert len(relative.parts) == 1
				(leaf/relative).write_bytes(archive.read(name))
		assert json.loads(archive.read('evidence/final-audit.json')) == audit
		assert json.loads(archive.read('history/previous-RESULT.json'))['final_commit'] == '0ce000667dd5cbee3e2af9fe0237b9c88a5536f3'
	decoder = load_module('resume_delivered_decoder', ROOT/'tools/qualification/encoded-evidence.py')
	_, data = decoder.decode(leaf/'effects25-r5-resume-encoding.json')
	packaging = read(leaf/'packaging.json')
	assert len(data) == packaging['archive_bytes'] and hashlib.sha256(data).hexdigest() == packaging['archive_sha256']
	path = leaf/'effects25-r5-resume-evidence.tar.xz'; path.write_bytes(data)
	if (leaf/'restore-chunks.py.txt').exists():
		codec = load_module('resume_delivered_chunks', ROOT/'tests/selfhost-effects/transport-chunks.py')
		assert (leaf/'restore-chunks.py.txt').read_bytes() == (ROOT/'tests/selfhost-effects/transport-chunks.py').read_bytes()
		standard_archive = leaf/'reconstructed-standard.tar.xz'; index = codec.decode(path, standard_archive)
		standard = dict(index); standard['format'] = 'astra-effects25-evidence/3'; standard.pop('storage')
		assert helpers.verify_archive(standard_archive) == standard
	else: standard_archive = path; index = helpers.verify_archive(path)
	assert len(index['files']) == packaging['logical_files'] and (index['final_commit'], index['final_tree']) == (result['final_commit'], result['final_tree'])
	helpers.restore_all(standard_archive, leaf, len(index['files']))
	previous = prior_transport(paths, paths.RUNTIME.parent/'report-history'/(PREVIOUS+'.zip'))
	old = helpers.verify_archive(previous)
	assert all(index['files'][name] == row for name, row in old['files'].items())
	for row in index['external_system_dependencies'].values():
		assert Path(row['path']).stat().st_size == Path(row['local_witness']).stat().st_size == row['bytes'] and sha(row['path']) == sha(row['local_witness']) == row['sha256']
	intake = read(paths.RUNTIME.parent/'native-current/pm-next-intake.json')
	assert intake['published'] and intake['report_sha256'] == sha(report) and (intake['final_commit'], intake['final_tree']) == (result['final_commit'], result['final_tree'])
	receipt = dict(status='PUBLISHED_R5_CONTINUATION_VERIFIED', G12='PASS: installed publisher followed by independent delivered ZIP/member/source/Git/transport verification', report=str(report), report_bytes=report.stat().st_size, report_sha256=sha(report), final_commit=result['final_commit'], final_tree=result['final_tree'], payloads=len(manifest['files']), logical_evidence_files=len(index['files']), preserved_previous_logical_files=len(old['files']), previous_report_sha256=PREVIOUS, original_flow_number_Astra_executions=audit['original_flow_number_Astra_executions'], overall_status=result['status'], limitation='G12 establishes delivery integrity only; it cannot promote any unproved source, owner, effects or memory gate.')
	(paths.RUNTIME/('published-verification-'+a.version+'.json')).write_text(json.dumps(receipt, indent=2)+'\n')
	print(json.dumps(receipt, indent=2), flush=True)


def main():
	p = argparse.ArgumentParser(); p.add_argument('mode', choices=('pack', 'verify')); p.add_argument('--version', required=True); p.add_argument('--audit', type=Path, required=True); p.add_argument('--seed-archive', type=Path); p.add_argument('--dictionary-mib', type=int, choices=(64, 256, 512, 1024), default=64); p.add_argument('--content-chunks', action='store_true'); p.add_argument('--digit-columns', action='store_true')
	a = p.parse_args(); assert a.version.isalnum() and a.audit.is_file()
	paths = load_module('resume_report_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	helpers = load_module('resume_transport_helpers', ROOT/'tests/selfhost-effects/recover-r5-report.py')
	if a.mode == 'pack': pack(paths, a, helpers)
	else: verify(paths, a, helpers)


if __name__ == '__main__':
	main()
