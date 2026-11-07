#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify the actual installed R3 publication and lossless evidence transport."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile
from state import ROOT, load_module, read, sha, git, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version', required=True); p.add_argument('--audit', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	assert not git('status', '--porcelain=v1', '--untracked-files=all').strip(); paths = load_module('r3_published_paths', ROOT/'tests/selfhost-effects/recover-build.py'); intake_recipe = load_module('r3_published_intake', ROOT/'tests/selfhost-effects/r3.py'); path = ROOT.parent/'codex/reports/astra-report-current.zip'; receipt_name = 'published-verification-'+a.version; leaf = paths.RUNTIME/receipt_name; leaf.mkdir()
	assert sha(paths.RUNTIME/'predecessor-report.zip') == intake_recipe.REPORT
	with zipfile.ZipFile(path) as z:
		assert z.testzip() is None and len(z.namelist()) == len(set(z.namelist())); manifest = json.loads(z.read('MANIFEST.json')); assert manifest['format'] == 'pm-codex-report/1' and set(z.namelist()) == {'MANIFEST.json', *(row['path'] for row in manifest['files'])}
		for row in manifest['files']:
			data = z.read(row['path']); assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256']
		result = json.loads(z.read('RESULT.json')); assert result['status'] == 'PARTIAL' and result['milestone_id'] == 'ASTRA-SELFHOST-EFFECTS-25-R3' and result['submission_sha256'] == '9a053524e182be20dbb143af6f6bcf735470678c616048795da59e98e422b982' and result['start_commit'] == intake_recipe.BASE and 'amendment' not in result
		assert (result['final_commit'], result['final_tree']) == (git('rev-parse', 'HEAD').strip(), git('rev-parse', 'HEAD^{tree}').strip()) and not result['final_dirty_tracked_paths'] and not result['untracked_inventory_changed']
		assert subprocess.run(['git', 'merge-base', '--is-ancestor', intake_recipe.BASE, result['final_commit']], cwd=ROOT).returncode == 0
		for name in z.namelist():
			if name.startswith('source/'): assert z.read(name) == subprocess.check_output(['git', 'show', result['final_commit']+':'+name.removeprefix('source/')], cwd=ROOT)
		audit = json.loads(z.read('evidence/final-audit.json')); assert audit == read(a.audit) and audit['previous_report_sha256'] == intake_recipe.REPORT and (audit['final_commit'], audit['final_tree']) == (result['final_commit'], result['final_tree']) and set(audit['gates']) == {'G'+str(i) for i in range(13)}
		assert all(p['retained_R2_programs'] == 60 and p['additional_programs'] >= 12 and p['additional_error_programs'] >= 8 and p['inherited_native_programs'] == p['inherited_raw_LLVM_identical'] == 202 for p in audit['profiles'].values())
		for name in z.namelist():
			if name.startswith('evidence/') and name != 'evidence/INDEX.json':
				part = Path(name.removeprefix('evidence/')); assert len(part.parts) == 1 and part.name == str(part); (leaf/part).write_bytes(z.read(name))
	packaging = read(leaf/'packaging.json'); decoder = load_module('r3_report_decoder', ROOT/'tools/qualification/encoded-evidence.py'); model, raw = decoder.decode(leaf/'effects25-completion-encoding.json'); assert hashlib.sha256(raw).hexdigest() == packaging['archive_sha256'] and len(raw) == packaging['archive_bytes']; archive = leaf/'effects25-completion-evidence.tar.xz'; archive.write_bytes(raw)
	argv = [sys.executable, '-B', ROOT/'tests/selfhost-effects/restore.py', archive, '--output', leaf/'decoded', '--verify-only']; r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/'restore.time', *argv], cwd=ROOT, capture_output=True, timeout=1200); (leaf/'restore.stdout').write_bytes(r.stdout); (leaf/'restore.stderr').write_bytes(r.stderr); assert r.returncode == 0, r.stderr[-2500:]; restored = json.loads(r.stdout); assert restored['status'] == 'BYTE_EXACT' and restored['logical_files'] == packaging['logical_files']
	intake = read(paths.RUNTIME.parent/'native-current/pm-next-intake.json'); assert intake['published'] and intake['milestone_id'] == result['milestone_id'] and intake['final_commit'] == result['final_commit'] and intake['final_tree'] == result['final_tree'] and intake['report_sha256'] == sha(path)
	assert sha(paths.RUNTIME/'predecessor-report.zip') == intake_recipe.REPORT
	receipt = dict(status='PUBLISHED_R3_PARTIAL_VERIFIED', report=str(path), report_bytes=path.stat().st_size, report_sha256=sha(path), final_commit=result['final_commit'], final_tree=result['final_tree'], payloads=len(manifest['files']), logical_evidence_files=restored['logical_files'], evidence_archive_sha256=packaging['archive_sha256'], previous_report_sha256=intake_recipe.REPORT, gates=dict(audit['gates'], G12='PASS: unchanged installed publisher and independent delivered ZIP/Git/manifest/lossless evidence verification'), remaining_boundary=audit['remaining_boundary'], classification='G12 passes publication integrity. The unfinished compiler gates and overall milestone remain PARTIAL.')
	(paths.RUNTIME/(receipt_name+'.json')).write_text(json.dumps(receipt, indent=2)+'\n'); print(json.dumps(receipt, indent=2), flush=True)


if __name__ == '__main__':
	main()
