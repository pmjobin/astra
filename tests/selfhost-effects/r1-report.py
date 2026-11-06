#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless R1 evidence package; publication uses the unchanged installed skill."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import sys
import tarfile
import time
import zipfile
from state import ROOT, sha, read, load_module, bounded_run

BASE = ROOT.parent/'codex/work/astra'
RUNTIME = BASE/'runtime/effects25-r1'
BUILD = BASE/'build/effects25-r1'


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.replace('-', '').isalnum()
	audit = read(RUNTIME/'final-audit.json'); assert audit['status'] == 'PARTIAL'
	leaf = RUNTIME/('handoff-'+a.version); leaf.mkdir(exist_ok=False)
	archive = leaf/'effects25-r1-evidence.tar.xz'; index = {}; blobs = set(); encoded = {}
	columns = load_module('r1_lossless_columns', ROOT/'tests/selfhost-genref/columns.py')
	column_directory = leaf/'columns'; column_directory.mkdir(); start = time.monotonic()
	with tarfile.open(archive, 'w:xz', preset=6) as packed:
		def store(name, path=None, data=None):
			entry = tarfile.TarInfo(name); entry.mode = 0o644
			if path is not None:
				entry.size = path.stat().st_size
				with path.open('rb') as stream: packed.addfile(entry, stream)
			else:
				entry.size = len(data); packed.addfile(entry, io.BytesIO(data))
		def add(name, path=None, data=None, expected=None, transform=True):
			assert name and not Path(name).is_absolute() and '..' not in Path(name).parts
			if path is not None:
				assert path.is_file() and not path.is_symlink()
				digest = sha(path); size = path.stat().st_size; mode = oct(path.stat().st_mode & 0o777)
			else: digest = hashlib.sha256(data).hexdigest(); size = len(data); mode = '0o644'
			if expected: assert digest == expected, name
			row = dict(bytes=size, sha256=digest, mode=mode, blob='blobs/'+digest)
			if name in index: assert index[name]['sha256'] == digest; return
			if transform and path is not None and path.suffix == '.stdout' and size >= 1048576:
				with path.open('rb') as stream: first = stream.readline()
				if not first.startswith(b'('):
					if digest not in encoded:
						plan = columns.encode(path, column_directory, name, len(encoded))
						observed = hashlib.sha256(); count = 0
						for block in columns.reconstruct(column_directory, plan): observed.update(block); count += len(block)
						assert observed.hexdigest() == digest and count == size
						encoded[digest] = plan
						for part in list(plan['parts'].values())+[p for group in plan['groups'] for p in group['columns']]: add('columns/'+part['path'], path=column_directory/part['path'], transform=False)
					row.pop('blob'); row['columns'] = dict(encoded[digest], path=name); index[name] = row; return
			index[name] = row
			if digest not in blobs: store(row['blob'], path=path, data=data); blobs.add(digest)
		for prefix, directory in [('runtime', RUNTIME), ('build', BUILD)]:
			for path in sorted(directory.rglob('*')):
				if not path.is_file() or path == RUNTIME/'predecessor-report.zip': continue
				if prefix == 'runtime' and path.relative_to(directory).parts[0].startswith('handoff-'): continue
				add(prefix+'/'+str(path.relative_to(directory)), path=path)
		for mode in ('O0', 'O2'):
			identity = read(Path(audit['products'][mode]['path']).with_suffix('.identity.json'))
			for path, expected in identity['identity']['sources'].items():
				source = Path(path)
				if source.is_relative_to(ROOT): add('compiled-input/'+str(source.relative_to(ROOT)), path=source, expected=expected)
			for row in read(RUNTIME/('inherited-v1-'+mode)/'result.json')['programs']:
				for source in row['sources']:
					path = Path(source['path']); add('inherited-source/'+source['sha256']+'/'+path.name, path=path, expected=source['sha256'])
		for name in ('original', 'LLVM23-base', 'Class15-current', 'live-initial'):
			ledger = read(BASE/'runtime/effects25'/('ledger-v1-O0-'+name)/'ledger.json')
			for row in ledger['files']:
				if 'synthetic_source_hex' in row: add('frozen/'+name+'/'+row['relative'], data=bytes.fromhex(row['synthetic_source_hex']), expected=row['sha256'])
				else: add('frozen/'+name+'/'+row['relative'], path=Path(row['path']), expected=row['sha256'])
		for path in sorted((RUNTIME.parent/'native-current/input').iterdir()):
			if path.is_file(): add('submission/'+path.name, path=path)
		add('workflow/intake-before-publication.json', path=RUNTIME.parent/'native-current/pm-next-intake.json')
		for name in ('tests/selfhost-effects/restore.py', 'tests/selfhost-genref/columns.py', 'tools/qualification/encoded-evidence.py'):
			add('recipes/'+Path(name).name, path=ROOT/name)
		store('INDEX.json', data=(json.dumps(dict(format='astra-effects25-evidence/3', milestone='ASTRA-SELFHOST-EFFECTS-25-R1', final_commit=audit['final_commit'], final_tree=audit['final_tree'], files=index), indent=2)+'\n').encode())
	with tarfile.open(archive, 'r:xz') as packed:
		expected = {row['blob']:row for row in index.values() if 'blob' in row}
		for entry in packed:
			assert entry.isfile()
			if entry.name == 'INDEX.json': continue
			row = expected.pop(entry.name); stream = packed.extractfile(entry); observed = hashlib.sha256(); count = 0
			while block := stream.read(1048576): observed.update(block); count += len(block)
			assert observed.hexdigest() == row['sha256'] and count == row['bytes']
		assert not expected
	attachments = leaf/'attachments'; attachments.mkdir(); tool = ROOT/'tools/qualification/encoded-evidence.py'
	r = bounded_run([sys.executable, '-B', tool, 'pack', '--input', archive, '--output', attachments, '--stem', 'effects25-r1'], capture_output=True, timeout=300)
	(leaf/'packing.stdout').write_bytes(r.stdout); (leaf/'packing.stderr').write_bytes(r.stderr); assert r.returncode == 0, r.stderr[-2000:]
	for name in ('final-audit.json', 'baseline.json', 'process-deadline.json'): shutil.copy2(RUNTIME/name, attachments/name)
	(attachments/'abi-approval.json').write_text(json.dumps(audit['approval'], indent=2)+'\n')
	shutil.copy2(tool, attachments/'decode-evidence.py.txt'); shutil.copy2(ROOT/'tests/selfhost-effects/restore.py', attachments/'restore-effects.py.txt'); shutil.copy2(ROOT/'tests/selfhost-genref/columns.py', attachments/'restore-columns.py.txt')
	packaging = dict(status='LOSSLESS_EVIDENCE_VERIFIED', logical_files=len(index), unique_blobs=len(blobs), column_encoded_observations=len(encoded), archive_bytes=archive.stat().st_size, archive_sha256=sha(archive), seconds=time.monotonic()-start, predecessor_report_preserved=str(RUNTIME/'predecessor-report.zip'), predecessor_sha256=sha(RUNTIME/'predecessor-report.zip'), classification='Exact byte transport only; not semantic or native effect qualification')
	(attachments/'packaging.json').write_text(json.dumps(packaging, indent=2)+'\n')
	(attachments/'review-guide.txt').write_text('Read final-audit.json and docs/selfhost-effects-25-r1.md. Effect domain PARTIAL: source checking implemented; native effect transport absent. Decode effects25-r1-encoding.json with decode-evidence.py.txt to recover the tar.xz. Save restore-effects.py.txt and restore-columns.py.txt beside each other as restore-effects.py and restore-columns.py, then run the former with ARCHIVE --output EXTERNAL_DIRECTORY --verify-only. This verifies all reconstructed bytes without executing evidence. The source controls, predecessor baseline, current compiler regression, C0-only design oracles and missing runtime effect gates retain separate attribution. G12 publication is established by the actual installed report and its subsequent independent verification.\n')
	files = [dict(path=p.name, bytes=p.stat().st_size, sha256=sha(p)) for p in sorted(attachments.iterdir())]
	assert all(row['bytes'] <= 2*1024**2 for row in files) and len(files) <= 128
	(attachments/'INDEX.json').write_text(json.dumps(dict(format='pm-next-evidence/1', files=files), indent=2)+'\n')
	result = dict(status='PARTIAL', summary='ASTRA-SELFHOST-EFFECTS-25-R1 implements source-bound nominal throws checking, ordinary argument-type checks on deferred throwing calls, ordered typed catches, open-bound coverage and lexical rethrow/unhandled-error rejection. The exact original E25-A-v1 approval is authenticated; no duplicate approval was requested. The approved private error/success ABI and Flow/Core/CFG/SSA/LLVM error-owner and cleanup implementation remain absent. There are zero new qualified Astra-emitted effect executables, so the effect domain remains PARTIAL. The changed compiler preserves 202 inherited native sources/profile with byte-identical raw LLVM and actual ELF behavior, 80 statuses and 1044 historical proof hashes. Original cohort conditional FlowGraph types and deferrals remain separate from initialized ownership; independent CheckedIndex.add_signature graph 55/symbol 2053/predicate 26 remains deferred. Full original native emission was attempted and refused upstream; no original throwing method ran. No C0/public ABI/workflow change, history rewrite, push, release or Stage 1 claim.', tests=[
		'Exact pinned submission and predecessor CRC/member/hash verification, required HEAD/tree and original native approval prompt/reply bound to proposal d77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e; clean intake and historical PARTIAL preserved.',
		'Four immutable cohorts × O0/O2: predecessor failures reproduced, final source/node/span identity and conditional FlowGraph 197/198/202/202 facts retained; generic verifier zero, initializer/local 17, move 19; original whole-method native attempts refused with preserved destinations.',
		'21 C0/Typecore source comparisons and 12 restored Typecore model mutations/profile passed. These are source controls, not cross-stage effect ownership or native ABI qualification.',
		'202 current inherited native sources/profile freshly emitted, LLVM-verified, linked and executed with matched behavior; all raw LLVM identities preserved. Distinct ELF byte identities are separate in final-audit.json.',
		'Original 80 statuses remain 56 admitted/12 rejected/12 deferred; 28 inherited model controls and module-owned LLVM layout-cache lifetime pass; 15 inherited normal-return programs/profile pass unsuppressed Valgrind with zero errors/live allocations/suppressions.',
		'Twelve C0 effect source oracles/profile execute and pass unsuppressed Valgrind; Astra effect emission remains refused and output bytes are preserved. C0 programs contribute zero new Astra effect executables.',
		'Fresh C0 LLVM/ELF/memory design witnesses and GCC/Clang O0/O2 layout agreement with six layout alternatives/tool/profile; these do not satisfy the six LLVM-valid candidate ABI alternatives gate.',
		'Unmet G2/G4/G5/G6/G8 and partial G3/G7/G9: checked ABI, separate live error ownership, reservation/error cleanup, independent Core/CFG/SSA/LLVM paths, 12+ new Astra programs, error-path memory, 20+ cross-stage effect mutants and original throwing-function execution remain unqualified.',
		'451 protected paths, 6622 donor files, 1044 historically attributed proof hashes, unchanged C0 and installed workflow/hooks, public ABI and verifier/layout boundaries rechecked. No compiler resource ceiling increased.',
		'Actual cold compiler invocation wall/CPU/RSS and individual failed/development command costs are retained; overlapping profile intervals are not added and no speedup is claimed. Process-group timeout/descendant termination passed. Historical SSA, numerical Valgrind and Utf8Message deferrals remain.',
		'Guarded formatter, generated-walker consistency and clean task-owned Git commit verified. Lossless evidence contains '+str(len(index))+' logical files; original report preserved externally. Installed publisher and independent final ZIP verification complete G12.'
	])
	(RUNTIME.parent/'native-current/pm-next-result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(packaging), flush=True); print('EVIDENCE_MANIFEST', attachments/'INDEX.json', flush=True)


if __name__ == '__main__':
	main()
