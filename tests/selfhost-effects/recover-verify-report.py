#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independently verify the installed amendment, its history and all evidence bytes."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile
from state import ROOT, load_module, read, sha, git, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version'); p.add_argument('--audit',type=Path); a = p.parse_args(); assert a.version is None or a.version.isalnum()
	assert not git('status','--porcelain=v1','--untracked-files=all').strip(); paths = load_module('recover_published_paths',ROOT/'tests/selfhost-effects/recover-build.py'); path = ROOT.parent/'codex/reports/astra-report-current.zip'; receipt_name = 'published-verification'+('-'+a.version if a.version else ''); leaf = paths.RUNTIME/receipt_name; leaf.mkdir()
	with zipfile.ZipFile(path) as z:
		assert z.testzip() is None and len(z.namelist()) == len(set(z.namelist())); manifest = json.loads(z.read('MANIFEST.json')); assert manifest['format'] == 'pm-codex-report/1' and set(z.namelist()) == {'MANIFEST.json',*(row['path'] for row in manifest['files'])}
		for row in manifest['files']:
			data = z.read(row['path']); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		result = json.loads(z.read('RESULT.json')); assert result['status'] == 'PARTIAL' and result['milestone_id'] == 'ASTRA-SELFHOST-EFFECTS-25-R2' and result['submission_sha256'] == '95899164ec3ab946f6e23e10c69c6e635d49bf70e5a03e05b028ce8d960c9244'; assert (result['final_commit'],result['final_tree']) == (git('rev-parse','HEAD').strip(),git('rev-parse','HEAD^{tree}').strip()) and not result['final_dirty_tracked_paths'] and not result['untracked_inventory_changed']; previous_sha = result['amendment']['previous_report_sha256']; assert len(previous_sha) == 64 and all(c in '0123456789abcdef' for c in previous_sha); history = paths.RUNTIME.parent/'report-history'/(previous_sha+'.zip'); assert sha(history) == previous_sha
		for name in z.namelist():
			if name.startswith('source/'): assert z.read(name) == subprocess.check_output(['git','show',result['final_commit']+':'+name.removeprefix('source/')],cwd=ROOT)
		with zipfile.ZipFile(history) as old:
			assert old.testzip() is None; assert z.read('history/previous-RESULT.json') == old.read('RESULT.json') and z.read('history/previous-REPORT.md') == old.read('REPORT.md'); previous = json.loads(old.read('RESULT.json')); assert result['amendment']['previous_final_commit'] == previous['final_commit'] and subprocess.run(['git','merge-base','--is-ancestor',previous['final_commit'],result['final_commit']],cwd=ROOT).returncode == 0
		audit = json.loads(z.read('evidence/final-audit.json')); assert audit == read(a.audit or paths.RUNTIME/'final-audit.json') and audit['previous_report_sha256'] == previous_sha and (audit['final_commit'],audit['final_tree']) == (result['final_commit'],result['final_tree']); assert all(profile['native_programs'] >= 12 and profile['actual_error_programs'] >= 8 and profile['success_cleanup_programs'] >= 4 and profile['inherited_native_programs'] == 202 and profile['inherited_raw_LLVM_identical'] == 202 for profile in audit['profiles'].values())
		for name in z.namelist():
			if name.startswith('evidence/') and name != 'evidence/INDEX.json':
				part = Path(name.removeprefix('evidence/')); assert len(part.parts) == 1 and part.name == str(part); (leaf/part).write_bytes(z.read(name))
	packaging = read(leaf/'packaging.json'); decoder = load_module('recover_report_decoder',ROOT/'tools/qualification/encoded-evidence.py'); model,raw = decoder.decode(leaf/'effects25-completion-encoding.json'); assert hashlib.sha256(raw).hexdigest() == packaging['archive_sha256'] and len(raw) == packaging['archive_bytes']; archive = leaf/'effects25-completion-evidence.tar.xz'; archive.write_bytes(raw)
	argv = [sys.executable,'-B',ROOT/'tests/selfhost-effects/restore.py',archive,'--output',leaf/'decoded','--verify-only']; r = bounded_run(['/usr/bin/time','-v','-o',leaf/'restore.time',*argv],cwd=ROOT,capture_output=True,timeout=1200); (leaf/'restore.stdout').write_bytes(r.stdout); (leaf/'restore.stderr').write_bytes(r.stderr); assert r.returncode == 0,r.stderr[-2500:]; restored = json.loads(r.stdout); assert restored['status'] == 'BYTE_EXACT' and restored['logical_files'] == packaging['logical_files']
	history = paths.RUNTIME.parent/'report-history'/(previous_sha+'.zip'); assert sha(history) == previous_sha; intake = read(paths.RUNTIME.parent/'native-current/pm-next-intake.json'); assert intake['published'] and intake['final_commit'] == result['final_commit'] and intake['report_sha256'] == sha(path)
	for checkpoint,expected in [(paths.RUNTIME/'checkpoint-report.zip','8cc90df9c524cd8a22ca0e9ba166920cff9962cc92a493691de64121aad5dc5a'),(paths.RUNTIME.parent/'effects25-r2/predecessor-report.zip','0b35b4382dc06074600731bcae4516171825ef9b4cab0dfbab653afab90a5395'),(paths.RUNTIME.parent/'effects25-r1/predecessor-report.zip','a3a364209b11e0d7c9e9ce337513764e9075d534b7ab5921dad25dcd9a50dcb3')]: assert sha(checkpoint) == expected
	receipt = dict(status='PUBLISHED_PARTIAL_AMENDMENT_VERIFIED',report=str(path),report_bytes=path.stat().st_size,report_sha256=sha(path),final_commit=result['final_commit'],final_tree=result['final_tree'],payloads=len(manifest['files']),logical_evidence_files=restored['logical_files'],evidence_archive_sha256=packaging['archive_sha256'],previous_report_sha256=previous_sha,previous_report_history=str(history),gates=audit['gates'],G12='PASS: unchanged installed publisher amendment and independent ZIP/Git/history/evidence verification',remaining_boundary=audit['remaining_boundary'],classification='Report integrity/publication verified; the remaining compiler implementation gates retain PARTIAL')
	(paths.RUNTIME/(receipt_name+'.json')).write_text(json.dumps(receipt,indent=2)+'\n'); print(json.dumps(receipt,indent=2),flush=True)


if __name__ == '__main__':
	main()
