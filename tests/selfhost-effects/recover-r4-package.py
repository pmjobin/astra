#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Lossless R4 evidence; the unchanged installed publisher alone writes the report."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import time
import zipfile
from state import ROOT, load_module, read, sha, bounded_run, git


def main():
	p = argparse.ArgumentParser(); p.add_argument('--audit', type=Path, required=True); p.add_argument('--version', required=True); p.add_argument('--reuse-columns',type=Path); a = p.parse_args(); assert a.version.isalnum(); audit = read(a.audit); assert audit['status'] == 'PARTIAL'
	assert (git('rev-parse','HEAD').strip(),git('rev-parse','HEAD^{tree}').strip()) == (audit['final_commit'],audit['final_tree']) and not git('status','--porcelain=v1','--untracked-files=all').strip()
	paths = load_module('recover_package_paths',ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('handoff-'+a.version); leaf.mkdir(); archive = leaf/'effects25-r4-evidence.tar.xz'; columns = load_module('recover_package_columns',ROOT/'tests/selfhost-genref/columns.py'); restore = load_module('recover_package_restore',ROOT/'tests/selfhost-effects/restore.py'); column_directory = leaf/'columns'; column_directory.mkdir(); index = {}; blobs = set(); encoded = {}; start = time.monotonic()
	reuse = {}; reused = []
	if a.reuse_columns:
		with zipfile.ZipFile(paths.RUNTIME/'predecessor-report.zip') as previous: previous_packaging = json.loads(previous.read('evidence/packaging.json'))
		old_archive = a.reuse_columns/'predecessor-evidence.tar.xz'; assert sha(old_archive) == previous_packaging['archive_sha256']
		with tarfile.open(old_archive,'r:xz') as old:
			old_index = json.load(old.extractfile('INDEX.json')); assert old_index['files']['recipes/columns.py']['sha256'] == sha(ROOT/'tests/selfhost-genref/columns.py')
			for row in old_index['files'].values():
				if 'columns' in row: reuse[row['sha256']] = row['columns']
				# The prior verify-only restore intentionally leaves no extracted data.
				# Materialize only authenticated, non-executable column transport parts.
			old_parts = {}
			for name,row in old_index['files'].items():
				if name.startswith('columns/'): old_parts.setdefault(row['blob'],[]).append((name.removeprefix('columns/'),row))
			old_columns = a.reuse_columns/'columns'; old_columns.mkdir(exist_ok=True)
			for member in old:
				if member.name not in old_parts: continue
				data = old.extractfile(member).read()
				for name,row in old_parts.pop(member.name):
					assert Path(name).name == name and len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
					target = old_columns/name
					if target.exists(): assert target.read_bytes() == data
					else: target.write_bytes(data)
			assert not old_parts
	with tarfile.open(archive,'w:xz',preset=9) as packed:
		def store(name,path=None,data=None):
			entry = tarfile.TarInfo(name); entry.mode = 0o644
			if path is None: entry.size = len(data); packed.addfile(entry,io.BytesIO(data))
			else:
				entry.size = path.stat().st_size
				with path.open('rb') as stream: packed.addfile(entry,stream)
		def add(name,path=None,data=None,expected=None,transform=True):
			assert name and not Path(name).is_absolute() and '..' not in Path(name).parts
			if path is not None: assert path.is_file() and not path.is_symlink(); digest = sha(path); size = path.stat().st_size; mode = oct(path.stat().st_mode&0o777)
			else: digest = hashlib.sha256(data).hexdigest(); size = len(data); mode = '0o644'
			if expected is not None: assert digest == expected,name
			if name in index: assert index[name]['sha256'] == digest; return
			row = dict(bytes=size,sha256=digest,mode=mode,blob='blobs/'+digest)
			if transform and path is not None and path.name == 'ledger.json':
				model = read(path)
				if model.get('format') == 'astra-whole-source-ledger/1':
					raw = path.with_name('whole-compiler.stdout'); assert raw.is_file(); model['nodes'] = None; model['raw_flow'] = None; metadata = leaf/(digest+'-metadata.json'); metadata.write_text(json.dumps(model,indent=2)+'\n'); rebuilt = restore.ledger(raw,metadata); assert len(rebuilt) == size and hashlib.sha256(rebuilt).hexdigest() == digest; del rebuilt,model
					raw_name = str(Path(name).with_name(raw.name)); metadata_name = 'ledger-metadata/'+digest+'.json'; add(raw_name,path=raw); add(metadata_name,path=metadata,transform=False); row.pop('blob'); row['ledger'] = dict(raw=raw_name,metadata=metadata_name); index[name] = row; return
			if transform and path is not None and (path.suffix == '.stdout' or path.name == 'stdout') and size >= 1048576:
				with path.open('rb') as stream: first = stream.readline()
				if not first.startswith(b'('):
					if digest not in encoded:
						if digest in reuse:
							plan = json.loads(json.dumps(reuse[digest])); assert plan['sha256'] == digest and plan['bytes'] == size
							for part in list(plan['parts'].values())+[p for group in plan['groups'] for p in group['columns']]:
								original = a.reuse_columns/'columns'/part['path']; assert sha(original) == part['sha256'] and original.stat().st_size == part['bytes']; part['path'] = 'reused-'+digest[:16]+'-'+part['path']; shutil.copy2(original,column_directory/part['path'])
							reused.append(digest)
						else: plan = columns.encode(path,column_directory,name,len(encoded))
						observed = hashlib.sha256(); count = 0
						for block in columns.reconstruct(column_directory,plan): observed.update(block); count += len(block)
						assert observed.hexdigest() == digest and count == size; encoded[digest] = plan
						for part in list(plan['parts'].values())+[p for group in plan['groups'] for p in group['columns']]: add('columns/'+part['path'],path=column_directory/part['path'],transform=False)
					row.pop('blob'); row['columns'] = dict(encoded[digest],path=name); index[name] = row; return
			index[name] = row
			if digest not in blobs: store(row['blob'],path=path,data=data); blobs.add(digest)
		for prefix,directory in [('runtime',paths.RUNTIME),('build',paths.BUILD)]:
			for path in sorted(directory.rglob('*')):
				if not path.is_file() or path.is_symlink(): continue
				parts = path.relative_to(directory).parts
				if prefix == 'runtime' and (parts[0].startswith('handoff-') or path.suffix == '.zip'): continue
				# Prior publication decoding only copies the already indexed archive
				# and attachments. Keep its actual verification output and receipt,
				# without nesting transport copies in the next transport archive.
				if prefix == 'runtime' and (parts[0].startswith('published-verification') or parts[0] == 'predecessor-verification') and len(parts) > 1 and path.name not in ('restore.stdout','restore.stderr','restore.time'): continue
				if prefix == 'runtime' and parts[0] == 'baseline-snapshots' and len(parts) > 1 and parts[1] not in ('O0','O2','products.json','result.json','restore.stdout','restore.stderr','restore.time'): continue
				add(prefix+'/'+str(path.relative_to(directory)),path=path)
		for mode,profile in audit['profiles'].items():
			identity = read(Path(profile['component']).with_suffix('.identity.json'))
			for name,expected in identity['identity']['sources'].items():
				path = Path(name)
				if path.is_relative_to(ROOT): add('compiled-input/'+str(path.relative_to(ROOT)),path=path,expected=expected)
			configuration = Path(audit['configuration_path']); assert sha(configuration) == audit['configuration_sha256']; regression = paths.RUNTIME/read(configuration)['profiles'][mode]['regression']
			for row in read(regression/('inherited-v1-'+mode)/'result.json')['programs']:
				for source in row['sources']: add('inherited-input/'+source['sha256']+'/'+Path(source['path']).name,path=Path(source['path']),expected=source['sha256'])
			for name in ('original','LLVM23-base','Class15-current','live-initial'):
				for row in read(regression/('ledger-v1-'+mode+'-'+name)/'ledger.json')['files']:
					logical = 'frozen/'+name+'/'+row['relative']
					if 'synthetic_source_hex' in row: add(logical,data=bytes.fromhex(row['synthetic_source_hex']),expected=row['sha256'])
					else: add(logical,path=Path(row['path']),expected=row['sha256'])
		packet = paths.RUNTIME.parent/'native-current/input'
		for path in sorted(packet.rglob('*')):
			if path.is_file(): add('submission/'+str(path.relative_to(packet)),path=path)
		add('workflow/intake-before-publication.json',path=paths.RUNTIME.parent/'native-current/pm-next-intake.json')
		old = Path(audit.get('previous_report_path', paths.RUNTIME/'predecessor-report.zip')); assert sha(old) == audit['previous_report_sha256']
		with zipfile.ZipFile(old) as previous:
			for name in ('RESULT.json','REPORT.md','MANIFEST.json','changes.patch'):
				if name in previous.namelist(): add('history/previous-'+name,data=previous.read(name))
		patches = subprocess.check_output(['git','format-patch','--stdout','--binary','776b91c28128c2d5e10b198d0fb510a7f587ac5f..'+audit['final_commit']],cwd=ROOT); add('history/continuation-commits.patch',data=patches)
		for name in ('tests/selfhost-effects/restore.py','tests/selfhost-genref/columns.py','tools/qualification/encoded-evidence.py'): add('recipes/'+Path(name).name,path=ROOT/name)
		store('INDEX.json',data=(json.dumps(dict(format='astra-effects25-evidence/3',milestone='ASTRA-SELFHOST-EFFECTS-25-R4',final_commit=audit['final_commit'],final_tree=audit['final_tree'],files=index),indent=2)+'\n').encode())
		# Reopen every stored blob independently; then exercise the actual decoder,
		# including reconstructed ledgers/columns, before creating attachments.
	with tarfile.open(archive,'r:xz') as packed:
		expected = {row['blob']:row for row in index.values() if 'blob' in row}
		for entry in packed:
			assert entry.isfile()
			if entry.name == 'INDEX.json': continue
			row = expected.pop(entry.name); stream = packed.extractfile(entry); observed = hashlib.sha256(); count = 0
			while block := stream.read(1048576): observed.update(block); count += len(block)
			assert observed.hexdigest() == row['sha256'] and count == row['bytes']
		assert not expected
	verify = leaf/'decoder-verification'; r = bounded_run([sys.executable,'-B',ROOT/'tests/selfhost-effects/restore.py',archive,'--output',verify,'--verify-only'],capture_output=True,timeout=1200); (leaf/'decoder.stdout').write_bytes(r.stdout); (leaf/'decoder.stderr').write_bytes(r.stderr); assert r.returncode == 0,r.stderr[-2500:]
	attachments = leaf/'attachments'; attachments.mkdir(); tool = ROOT/'tools/qualification/encoded-evidence.py'; r = bounded_run([sys.executable,'-B',tool,'pack','--input',archive,'--output',attachments,'--stem','effects25-r4'],capture_output=True,timeout=300); (leaf/'packing.stdout').write_bytes(r.stdout); (leaf/'packing.stderr').write_bytes(r.stderr); assert r.returncode == 0,r.stderr[-2500:]
	shutil.copy2(a.audit,attachments/'final-audit.json'); shutil.copy2(tool,attachments/'decode-evidence.py.txt'); shutil.copy2(ROOT/'tests/selfhost-effects/restore.py',attachments/'restore-effects.py.txt'); shutil.copy2(ROOT/'tests/selfhost-genref/columns.py',attachments/'restore-columns.py.txt')
	packaging = dict(status='LOSSLESS_EVIDENCE_VERIFIED',logical_files=len(index),unique_blobs=len(blobs),column_observations=len(encoded),byte_exact_column_reuse=reused,column_reuse_limitation='Transport encoding reuse only; every reconstructed observation is hashed again, with no semantic/runtime credit from reuse.',prior_publication_decoding='Generated attachment/archive copies are excluded; actual restore stdout/stderr/time and verification receipts are retained. The exact R3 predecessor ZIP is preserved in runtime/effects25-r4/predecessor-report.zip; earlier reports and amendment archives remain historical.',archive_bytes=archive.stat().st_size,archive_sha256=sha(archive),seconds=time.monotonic()-start,previous_report_sha256=sha(old), baseline_transport_copies='Previously verified R3 attachment/archive copies are excluded; its immutable source snapshots, verification receipts and actual fresh baseline executions are retained.'); (attachments/'packaging.json').write_text(json.dumps(packaging,indent=2)+'\n')
	(attachments/'review-guide.txt').write_text('Read final-audit.json for exact gates, native counts, original-source attempts, costs and deferrals. Decode effects25-r4-encoding.json using decode-evidence.py.txt to recover the tar.xz. Save restore-effects.py.txt and restore-columns.py.txt together as restore-effects.py and restore-columns.py; run restore-effects.py ARCHIVE --output DIRECTORY --verify-only to verify all logical bytes without executing evidence. Original/R1/R2/R3 PARTIAL checkpoints retain their identities and Git history. ABI caller adapters and independent C/C++/C0 probes have zero Astra program credit. Installed publication plus its independent ZIP verification establishes G12.\n')
	files = [dict(path=path.name,bytes=path.stat().st_size,sha256=sha(path)) for path in sorted(attachments.iterdir())]; assert all(row['bytes'] <= 2*1024**2 for row in files) and len(files) <= 128; manifest = attachments/'INDEX.json'; manifest.write_text(json.dumps(dict(format='pm-next-evidence/1',files=files),indent=2)+'\n')
	counts = ', '.join(mode+': '+str(profile['total_source_programs'])+' native source programs, including '+str(profile['retained_effect_programs'])+' retained effects and '+str(profile['additional_programs'])+' new programs ('+str(profile['additional_error_programs'])+' new error paths)' for mode,profile in audit['profiles'].items())
	descriptor = dict(status='PARTIAL',summary='ASTRA-SELFHOST-EFFECTS-25-R4 implements finite nominal Class fields with independently checked source receiver slots, constructor initialization, reverse cleanup, owner transfer/replacement and complete buffer exchange; C0-valid copied nonvoid discards; ordinary snapshot and zero-buffer allocation policy; and source-bound scalar/length getters. '+counts+'. Approved private E25-A-v1, C0, public ABI, LLVM23, all historical checkpoints and independent verifiers remain intact. Remaining mandatory work: '+audit['remaining_boundary']+' Original unchanged flow_number has no Astra execution. No Stage 1, release, push, history rewrite or narrowed PASS.',tests=['R3 '+key+': '+value for key,value in audit['gates'].items()]+['R4 TASK '+key+': '+value for key,value in audit['r4_task_gates'].items()]+['Full raw LLVM and ELF identities are separately recorded; the required zero-buffer helper correction is explicit and never called raw byte equivalence.','All attached logical bytes were independently reconstructed and verified before installed publication. Cold/warm/failed/superseded costs retain actual wall/CPU/RSS and overlap attribution.','Committed recover-r4-verify-report.py verifies the delivered ZIP, source/Git identities, complete evidence transport and actual publication outcome separately.'])
	(leaf/'pm-next-result.json').write_text(json.dumps(descriptor,indent=2)+'\n'); print(json.dumps(packaging),flush=True); print('EVIDENCE_MANIFEST',manifest,flush=True); print('RESULT_DESCRIPTOR',leaf/'pm-next-result.json',flush=True)


if __name__ == '__main__':
	main()
