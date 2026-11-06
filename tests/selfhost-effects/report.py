#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless evidence preparation; publication stays with installed pm-next."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import stat
import subprocess
import time
import tarfile
from state import ROOT, RUNTIME, BUILD, PRIOR, COHORTS, read, sha, load_module


def main():
	start = time.monotonic(); audit = read(RUNTIME/'final-audit.json'); assert audit['status'] == 'PARTIAL'
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--reuse-columns'); a = p.parse_args(); assert a.version.replace('-', '').isalnum()
	leaf = RUNTIME/('handoff-'+a.version); leaf.mkdir(exist_ok=False); archive = leaf/'effects25-evidence.tar.xz'
	index = {}; blobs = set(); encoded = {}; omissions = []
	columns = load_module('effects_lossless_columns', ROOT/'tests/selfhost-genref/columns.py'); column_directory = leaf/'columns'; column_directory.mkdir()
	reuse = {}; reused = []
	if a.reuse_columns:
		assert a.reuse_columns.replace('-', '').isalnum()
		previous = RUNTIME/('handoff-'+a.reuse_columns)
		with tarfile.open(previous/'effects25-evidence.tar.xz', 'r:xz') as old:
			model = json.load(old.extractfile('INDEX.json')); assert model['format'] == 'astra-effects25-evidence/2'
			for row in model['files'].values():
				if 'columns' in row: reuse[row['sha256']] = row['columns']
	with tarfile.open(archive, 'w:xz', preset=9) as z:
		def store(name, path=None, data=None):
			entry = tarfile.TarInfo(name); entry.mode = 0o644
			if path is not None:
				entry.size = path.stat().st_size
				with path.open('rb') as stream: z.addfile(entry, stream)
			else:
				entry.size = len(data); z.addfile(entry, io.BytesIO(data))
		def add(name, path=None, data=None, expected=None, transform=True):
			assert not Path(name).is_absolute() and '..' not in Path(name).parts
			if path is not None:
				assert path.is_file() and not path.is_symlink(); digest = sha(path); size = path.stat().st_size; mode = oct(path.stat().st_mode & 0o777)
			else:
				digest = hashlib.sha256(data).hexdigest(); size = len(data); mode = '0o644'
			if expected: assert digest == expected
			row = dict(bytes=size, sha256=digest, mode=mode, blob='blobs/'+digest)
			if name in index: assert index[name] == row; return
			if transform and path is not None and path.suffix == '.stdout' and size >= 1048576:
				with path.open('rb') as stream: first = stream.readline()
				if not first.startswith(b'('):
					if digest not in encoded:
						ordinal = len(encoded)
						if digest in reuse:
							plan = json.loads(json.dumps(reuse[digest])); assert plan['sha256'] == digest and plan['bytes'] == size
							parts = list(plan['parts'].values())+[part for group in plan['groups'] for part in group['columns']]
							for part in parts:
								original = previous/'columns'/part['path']; assert sha(original) == part['sha256'] and original.stat().st_size == part['bytes']
								part['path'] = 'cached-'+digest[:16]+'-'+part['path']; shutil.copy2(original, column_directory/part['path'])
							reused.append(dict(sha256=digest, bytes=size, previous=str(previous), verification='Previously byte-exact reconstructed plan; identical input hash, schema, decoder and part hashes. Logical filename is metadata only.'))
						else:
							plan = columns.encode(path, column_directory, name, ordinal)
							observed = hashlib.sha256(); count = 0
							for block in columns.reconstruct(column_directory, plan): observed.update(block); count += len(block)
							assert observed.hexdigest() == digest and count == size
						encoded[digest] = plan
						for part in list(plan['parts'].values())+[part for group in plan['groups'] for part in group['columns']]: add('columns/'+part['path'], path=column_directory/part['path'], transform=False)
					row.pop('blob'); row['columns'] = dict(encoded[digest], path=name); index[name] = row; return
			index[name] = row
			if digest not in blobs:
				store(row['blob'], path=path, data=data)
				blobs.add(digest)
		add('recipes/restore-columns.py', path=ROOT/'tests/selfhost-genref/columns.py')
		add('recipes/restore-effects.py', path=ROOT/'tests/selfhost-effects/restore.py')
		for prefix, directory in [('runtime', RUNTIME), ('build', BUILD)]:
			for path in sorted(directory.rglob('*')):
				if not path.is_file() or path == RUNTIME/'predecessor-report.zip': continue
				if prefix == 'runtime' and path.relative_to(directory).parts[0].startswith('handoff-'):
					if path.name in ('effects25-evidence.zip', 'packaging.json', 'effects25-encoding.json'): omissions.append(dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path), reason='Earlier oversized transport remains preserved externally; underlying engineering files are included losslessly in this replacement.'))
					continue
				add(prefix+'/'+str(path.relative_to(directory)), path=path)
		for name in COHORTS:
			ledger = read(PRIOR/('ledger-v3-O0-'+name)/'ledger.json')
			for row in ledger['files']:
				logical = 'frozen/'+name+'/'+row['relative']
				if 'synthetic_source_hex' in row: add(logical, data=bytes.fromhex(row['synthetic_source_hex']), expected=row['sha256'])
				else: add(logical, path=Path(row['path']), expected=row['sha256'])
		for mode in ('O0', 'O2'):
			identity = read(Path(audit['products'][mode]['path']).with_suffix('.identity.json'))
			for path, expected in identity['identity']['sources'].items():
				source = Path(path)
				if source.is_relative_to(ROOT): add('compiled-input/'+str(source.relative_to(ROOT)), path=source, expected=expected)
			for row in read(RUNTIME/('inherited-v1-'+mode)/'result.json')['programs']:
				for source in row['sources']:
					path = Path(source['path']); add('inherited-source/'+source['sha256']+'/'+path.name, path=path, expected=source['sha256'])
		store('INDEX.json', data=(json.dumps(dict(format='astra-effects25-evidence/2', files=index, preserved_external_transports=omissions), indent=2)+'\n').encode())
	with tarfile.open(archive, 'r:xz') as z:
		remaining = {row['blob']: row for row in index.values() if 'blob' in row}
		for entry in z:
			assert entry.isfile()
			if entry.name == 'INDEX.json': continue
			row = remaining.pop(entry.name)
			h = hashlib.sha256(); size = 0
			with z.extractfile(entry) as f:
				for block in iter(lambda: f.read(1048576), b''): h.update(block); size += len(block)
			assert h.hexdigest() == row['sha256'] and size == row['bytes']
		assert not remaining
	attachments = leaf/'attachments'; attachments.mkdir()
	tool = ROOT/'tools/qualification/encoded-evidence.py'
	r = subprocess.run(['python3', '-B', tool, 'pack', '--input', archive, '--output', attachments, '--stem', 'effects25'], capture_output=True); assert r.returncode == 0, r.stderr[-2000:]
	(leaf/'packing.stdout').write_bytes(r.stdout); (leaf/'packing.stderr').write_bytes(r.stderr)
	for name in ('final-audit.json', 'abi-approval.json', 'baseline.json', 'process-deadline.json'):
		shutil.copy2(RUNTIME/name, attachments/name)
	shutil.copy2(tool, attachments/'decode-evidence.py.txt')
	shutil.copy2(ROOT/'tests/selfhost-genref/columns.py', attachments/'restore-columns.py.txt')
	shutil.copy2(ROOT/'tests/selfhost-effects/restore.py', attachments/'restore-effects.py.txt')
	(attachments/'review-guide.txt').write_text('Read final-audit.json and docs/selfhost-effects-25.md first: engineering PARTIAL, E25-A-v1 approved but unimplemented. Decode effects25-encoding.json with decode-evidence.py.txt to recover the tar.xz. Save restore-columns.py.txt beside restore-effects.py.txt as restore-columns.py; then run the latter with ARCHIVE --output EXTERNAL_DIRECTORY --verify-only to verify every reconstructed byte, or omit --verify-only to restore. INDEX.json maps logical files to hashed blobs/ members or byte-exact token-column plans. All original modes, byte counts and SHA-256 values are indexed. Column reconstruction was checked before initial packing; exact input/schema/decoder/part reuse is separately recorded. Archive blob hashes were checked on reopen. Prior oversized transports remain externally preserved with hashes; no engineering observations are dropped. Transport verification is not a compiler safety proof.\n')
	packaging = dict(status='LOSSLESS_EVIDENCE_VERIFIED', logical_files=len(index), unique_blobs=len(blobs), column_encoded_observations=len(encoded), exact_column_reuse=reused, raw_archive_bytes=archive.stat().st_size, raw_archive_sha256=sha(archive), seconds=time.monotonic()-start, original_GENREF24_report_preserved=str(RUNTIME/'predecessor-report.zip'), predecessor_sha256=sha(RUNTIME/'predecessor-report.zip'), preserved_external_transports=omissions, archive_format='INDEX.json maps exact logical files to hashed blobs or verified lossless token columns; original modes and byte identities are retained. C0/baseline/source and failed attempts keep their attribution.')
	(attachments/'packaging.json').write_text(json.dumps(packaging, indent=2)+'\n')
	files = [dict(path=p.name, bytes=p.stat().st_size, sha256=sha(p)) for p in sorted(attachments.iterdir())]
	assert all(row['bytes'] <= 2*1024**2 for row in files) and sum(row['bytes'] for row in files) <= 64*1024**2 and len(files) <= 128
	(attachments/'INDEX.json').write_text(json.dumps(dict(format='pm-next-evidence/1', files=files), indent=2)+'\n')
	profiles = audit['profiles']; cost = '; '.join(mode+' cold '+str(profiles[mode]['cold_build'].get('wall_seconds'))+' s / '+str(profiles[mode]['cold_build'].get('peak_RSS_KiB'))+' KiB RSS' for mode in ('O0', 'O2'))
	result = dict(status='PARTIAL', summary='EFFECTS-25 static producer/local/move type repair qualified on all four exact frozen populations. The first missing fact was checked_call rejecting throws flag 64 before reading an existing nominal owned result; local/argument now have exact FlowGraph TypeIds 197/198/202/202 while call/local deferral 17 and move obligation 19 remain. Generic verification returns zero, but complete Flow still fails unsupported effects, Class-origin policy and independent owner-capture authority. E25-A-v1 was explicitly APPROVED in this session; its recoverable-error ABI, cleanup and full IR/native implementation remain unimplemented, so this is an engineering PARTIAL, not an approval-required checkpoint or milestone PASS. All 202 inherited native identities/profile freshly emit byte-identical LLVM and execute with matched behavior. Twelve new C0 source oracles/profile execute with unsuppressed Valgrind; zero new Astra effect executables qualify. Historical statuses/proofs, donor, protected paths, C0, LLVM23, public ABI and verification boundaries are preserved. '+cost+'.', tests=[
		'Installed unchanged pm-next exact ZIP intake; pinned HEAD/tree, GENREF-24 report, config/hooks/refs/stashes/worktrees, 451 protected paths, 6622 donor files and 1044 historical proof hashes verified; no historical report rewrite.',
		'Baseline: eight exact O0/O2 consumers reproduce CHECKED_CONSUMER 1 25; reason 13, graph local and move TypeId 0, owning flag 4 and obligation 19. Source/node/span populations remain exact.',
		'Final source observers and matched ledgers: nominal FlowGraph result/local/move 197/198/202/202; exact Error bound and flags 68 retained; call/local deferral 17, move 19; original earlier calls remain type 1/flags 0/obligation 19. Separate unchanged generic verifier returns zero; independent full Flow consumer exits 1.',
		'Flow diagnostic: first original BAD_GRAPH is CheckedIndex.add_signature, graph 55/symbol 2053, owner-capture predicate 26; this.signatures has no admitted root slot. No source/storage/ownership verifier relaxation.',
		'C0 independent exact whole-method ASTs: owned flow_graph and flow_index retain throws Error; complete original method native execution is unqualified. Whole-cohort C0 semantic check timed out at 240 s; orphan overrun and termination are retained; no increased compiler limit.',
		'E25-A-v1 explicit user approval bound to proposal SHA-256 d77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e. GCC/Clang O0/O2 agree with C0 LLVM root error layout; six design layout alternatives/profile rejected. These are design checks, not new Astra ABI mutation qualification.',
		'O0/O2 native baseline: 202 exact source identities/profile freshly recompiled, LLVM-verified, assembled/linked and executed; all 202 raw LLVM identities/profile retained. Distinct ELF byte counts are reported separately in final-audit.json.',
		'O0/O2 continuity: original 80 statuses remain 56 admitted/12 rejected/12 deferred; module-owned LLVM layout-cache lifetime and 28 inherited model negatives pass. They are excluded from new effect mutation counts.',
		'O0/O2 static controls: Parcel/Ripple/generic-container conditional result typing, mismatched nominal, undefined return, unhandled effect, borrowed move and nonthrowing controls preserve refusals. Fifteen inherited normal-return native programs/profile pass fresh unsuppressed Valgrind with zero errors/live allocations/suppressions.',
		'Twelve new C0 error/success oracles/profile pass native execution and unsuppressed Valgrind; actual Astra Core admission refuses all twelve and preserves existing output bytes. Zero new qualified Astra recoverable-effect executables, error-return memory pairs or new effect model/LLVM physical mutants: G4/G5/G7/G8 remain unmet.',
		'Guarded source formatter and final clean Git/source/product audit pass. Exact cold/warm reuse and failed/candidate costs are retained; no matched-workload speedup claim. Two inherited SSA work-limit deferrals, wide-u64/f32 Valgrind disagreement, complete Utf8Message factory and Stage 1 remain unqualified.',
		'Lossless evidence archive verified: '+str(len(index))+' logical files / '+str(len(blobs))+' unique blobs; bounded gzip/base64 transport through the unchanged installed publisher.'
	])
	(RUNTIME.parent/'native-current/pm-next-result.json').write_text(json.dumps(result, indent=2)+'\n')
	print(json.dumps(packaging, indent=2), flush=True); print('EVIDENCE_MANIFEST', attachments/'INDEX.json', flush=True)


if __name__ == '__main__':
	main()
