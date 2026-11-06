#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless R2 evidence package; publication uses the unchanged installed skill."""
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
RUNTIME = BASE/'runtime/effects25-r2'
BUILD = BASE/'build/effects25-r2'


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--reuse-columns'); a = p.parse_args(); assert a.version.replace('-', '').isalnum()
	audit = read(RUNTIME/'final-audit.json'); assert audit['status'] == 'PARTIAL'
	leaf = RUNTIME/('handoff-'+a.version); leaf.mkdir(exist_ok=False)
	archive = leaf/'effects25-r2-evidence.tar.xz'; index = {}; blobs = set(); encoded = {}
	columns = load_module('r1_lossless_columns', ROOT/'tests/selfhost-genref/columns.py')
	restore = load_module('r1_ledger_decoder', ROOT/'tests/selfhost-effects/restore.py')
	reuse = {}; reused = []
	if a.reuse_columns:
		assert a.reuse_columns.replace('-', '').isalnum()
		previous = RUNTIME/('handoff-'+a.reuse_columns)
		with tarfile.open(previous/'effects25-r2-evidence.tar.xz', 'r:xz') as old:
			model = json.load(old.extractfile('INDEX.json'))
			assert model['files']['recipes/columns.py']['sha256'] == sha(ROOT/'tests/selfhost-genref/columns.py')
			for row in model['files'].values():
				if 'columns' in row: reuse[row['sha256']] = row['columns']
	column_directory = leaf/'columns'; column_directory.mkdir(); start = time.monotonic()
	with tarfile.open(archive, 'w:xz', preset=9) as packed:
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
			if transform and path is not None and path.name == 'ledger.json':
				model = read(path)
				if model.get('format') == 'astra-whole-source-ledger/1':
					raw = path.with_name('whole-compiler.stdout'); assert raw.is_file()
					model['nodes'] = None; model['raw_flow'] = None
					metadata = leaf/(digest+'-metadata.json'); metadata.write_text(json.dumps(model, indent=2)+'\n')
					data = restore.ledger(raw, metadata); assert len(data) == size and hashlib.sha256(data).hexdigest() == digest
					del data, model
					raw_name = str(Path(name).with_name('whole-compiler.stdout')); metadata_name = 'ledger-metadata/'+digest+'.json'
					add(raw_name, path=raw); add(metadata_name, path=metadata, transform=False)
					row.pop('blob'); row['ledger'] = dict(raw=raw_name, metadata=metadata_name); index[name] = row; return
			if transform and path is not None and (path.suffix == '.stdout' or path.name == 'stdout') and size >= 1048576:
				with path.open('rb') as stream: first = stream.readline()
				if not first.startswith(b'('):
					if digest not in encoded:
						if digest in reuse:
							plan = json.loads(json.dumps(reuse[digest])); assert plan['sha256'] == digest and plan['bytes'] == size
							for part in list(plan['parts'].values())+[p for group in plan['groups'] for p in group['columns']]:
								original = previous/'columns'/part['path']; assert sha(original) == part['sha256'] and original.stat().st_size == part['bytes']
								part['path'] = 'cached-'+digest[:16]+'-'+part['path']; shutil.copy2(original, column_directory/part['path'])
							reused.append(dict(sha256=digest, previous=str(previous), verification='Previously reconstructed identical bytes; exact source, decoder and part hashes rechecked'))
						else:
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
				# The exact R1 archive is preserved externally and authenticated in
				# predecessor-verified.json; do not duplicate its entire transport.
				if prefix == 'runtime' and path.is_relative_to(RUNTIME/'predecessor-verification'): continue
				if prefix == 'runtime' and path.relative_to(directory).parts[0].startswith('handoff-'): continue
				add(prefix+'/'+str(path.relative_to(directory)), path=path)
		for name in ('final-audit.json', 'abi-approval.json', 'packaging.json'):
			add('historical-R1/'+name, path=RUNTIME/'predecessor-verification'/name)
		for mode in ('O0', 'O2'):
			identity = read(Path(audit['products'][mode]['path']).with_suffix('.identity.json'))
			for path, expected in identity['identity']['sources'].items():
				source = Path(path)
				if source.is_relative_to(ROOT): add('compiled-input/'+str(source.relative_to(ROOT)), path=source, expected=expected)
			for row in read(RUNTIME/'final'/('inherited-v1-'+mode)/'result.json')['programs']:
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
		store('INDEX.json', data=(json.dumps(dict(format='astra-effects25-evidence/3', milestone='ASTRA-SELFHOST-EFFECTS-25-R2', final_commit=audit['final_commit'], final_tree=audit['final_tree'], files=index), indent=2)+'\n').encode())
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
	r = bounded_run([sys.executable, '-B', tool, 'pack', '--input', archive, '--output', attachments, '--stem', 'effects25-r2'], capture_output=True, timeout=300)
	(leaf/'packing.stdout').write_bytes(r.stdout); (leaf/'packing.stderr').write_bytes(r.stderr); assert r.returncode == 0, r.stderr[-2000:]
	for name in ('final-audit.json', 'process-deadline.json', 'predecessor-verified.json'): shutil.copy2(RUNTIME/name, attachments/name)
	(attachments/'abi-approval.json').write_text(json.dumps(audit['approval'], indent=2)+'\n')
	shutil.copy2(tool, attachments/'decode-evidence.py.txt'); shutil.copy2(ROOT/'tests/selfhost-effects/restore.py', attachments/'restore-effects.py.txt'); shutil.copy2(ROOT/'tests/selfhost-genref/columns.py', attachments/'restore-columns.py.txt')
	packaging = dict(status='LOSSLESS_EVIDENCE_VERIFIED', logical_files=len(index), unique_blobs=len(blobs), column_encoded_observations=len(encoded), exact_column_reuse=reused, archive_bytes=archive.stat().st_size, archive_sha256=sha(archive), seconds=time.monotonic()-start, predecessor_report_preserved=str(RUNTIME/'predecessor-report.zip'), predecessor_sha256=sha(RUNTIME/'predecessor-report.zip'), classification='Exact byte transport only; not semantic or native effect qualification')
	(attachments/'packaging.json').write_text(json.dumps(packaging, indent=2)+'\n')
	(attachments/'review-guide.txt').write_text('Read final-audit.json and docs/selfhost-effects-25-r2.md. Effect domain PARTIAL: scalar/void physical signature contracts only; native effect bodies absent. Unreachable LLVM fixtures are not effect ELFs or cross-stage ownership proofs. Decode effects25-r2-encoding.json with decode-evidence.py.txt to recover the tar.xz. Save restore-effects.py.txt and restore-columns.py.txt beside each other as restore-effects.py and restore-columns.py, then run the former with ARCHIVE --output EXTERNAL_DIRECTORY --verify-only. This verifies all reconstructed bytes without executing evidence. The source controls, predecessor baseline, current compiler regression, C0-only design oracles and missing runtime effect gates retain separate attribution. G12 publication is established by the actual installed report and its subsequent independent verification.\n')
	files = [dict(path=p.name, bytes=p.stat().st_size, sha256=sha(p)) for p in sorted(attachments.iterdir())]
	assert all(row['bytes'] <= 2*1024**2 for row in files) and len(files) <= 128
	(attachments/'INDEX.json').write_text(json.dumps(dict(format='pm-next-evidence/1', files=files), indent=2)+'\n')
	result = dict(status='PARTIAL', summary='ASTRA-SELFHOST-EFFECTS-25-R2 authenticates the original E25-A-v1 approval and preserves the original/R1 PARTIAL checkpoints. It adds an owner-bound scalar/void checked ABI declaration plan, actual LLVM signature construction and an independent physical signature verifier, plus explicit refusal of checked signatures at the ordinary native ABI boundary. It does not implement recoverable-error bodies: zero new Astra effect ELFs qualify. Minimal void/scalar success/error emission is attempted at both profiles and refused at Core 3 on incomplete Flow, including Error TYPE_POLICY 7, constructor/effect deferrals and unsupported throw/try control. The approved owned Error layout/allocation/destruction, Flow error ownership/reservations, Core/CFG/SSA operations and LLVM success/error body lowering remain unimplemented. Current compilers retain all 202 inherited native sources/profile with byte-identical raw LLVM and actual native execution. Original source cohorts retain their conditional TypeIds and obligations; CheckedIndex predicate 26 remains independently deferred and no original throwing function executes. No C0/public ABI/LLVM/resource/workflow/history change, push, release or Stage 1 claim.', tests=[
		'Exact R2 ZIP hash and pinned Git HEAD/tree verified through unchanged installed pm-next; R1 report CRC/manifest/source/Git and original native approval prompt/reply/proposal authenticated; historical PARTIAL reports preserved.',
		'Four frozen cohorts per profile freshly replayed; final complete source/node/kind/span ledgers match original 79/85/92/92 files and 174297/188293/206465/208328 nodes; FlowGraph TypeIds 197/198/202/202, initializer/local 17 and move 19 retained.',
		'202 inherited native sources per profile freshly emitted/LLVM-verified/linked/executed with old raw LLVM identities; distinct ELF hashes separately counted: 202 O0, 182 O2. Original 80 statuses remain 56 admitted/12 rejected/12 deferred.',
		'28 inherited model controls, 10 source negatives and module-owned LLVM layout-cache lifetime controls/profile pass. Fifteen inherited normal-return programs/profile pass unsuppressed Valgrind with zero errors/live allocations/suppressions.',
		'Four minimal void/scalar success/error sources/profile: independent unchanged C0 execution, Valgrind and actual checked entry signatures pass. Genuine Astra emission fails upstream and preserves output destinations: no new Astra error ELF or error-return memory qualification.',
		'Six admitted scalar/void signature sources and five explicitly deferred carrier/generic/nonthrowing controls/profile. Thirteen ABI plan mutation categories and seven LLVM-valid signature alternatives/source reject with valid controls. Fixture bodies are unreachable; these count as zero cross-stage/error-body effect mutation categories.',
		'Twelve separate C0 recoverable-effect oracles/profile execute with zero unsuppressed Valgrind errors; Astra refusal retained. Fresh C0 LLVM/ELF/memory and GCC/Clang layout probes agree; these do not constitute Astra allocation, dynamic destruction or layout authority.',
		'Unchanged original native compilation attempts refuse upstream; no original throwing method executes. Graph 55/symbol 2053 CheckedIndex.add_signature predicate 26 remains deferred: this.signatures field/root slot 0 versus grown slot 6.',
		'G2/G4/G5/G6/G8 NOT_MET; G3/G7/G9 PARTIAL. Remaining work includes exact Error ownership and layout, checked-call control/reservations, independently verified Core/CFG/SSA/LLVM effects, 12+ new Astra programs/profile, eight error paths, original source execution, 20 cross-stage mutants and six LLVM-valid error-body alternatives.',
		'451 protected paths, 6622 read-only donor files, 1044 historical proof hashes, C0, installed workflow/hooks and original/R1 documentation rehashed unchanged. Existing SSA, numerical Valgrind and Utf8Message deferrals remain separately unqualified.',
		'Cold and warm costs with wall/CPU/RSS and interval overlap are in final-audit.json. Exact warm reuse is not compilation. Bounded descendant termination verified; failed routing, source-check and oracle-probe attempts remain preserved. No compiler ceiling increased.',
		'Guarded formatting and clean task-owned Git commit verified. Lossless evidence contains '+str(len(index))+' logical files; installed publication and independent report verification establish G12 without changing the missing engineering gates.'
	])
	(RUNTIME.parent/'native-current/pm-next-result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(packaging), flush=True); print('EVIDENCE_MANIFEST', attachments/'INDEX.json', flush=True)


if __name__ == '__main__':
	main()
