#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Separate after-publication G5: exact delivery and fresh live modern native proof."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import zipfile

from support import execute, output_path, sha, write

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('audit', 'build', 'runtime'): p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	runtime = output_path(a.runtime, WORK/'runtime'); build = output_path(a.build, WORK/'build')
	runtime.mkdir(parents=True, exist_ok=False); build.mkdir(parents=True, exist_ok=False)
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	started = time.time_ns(); assert started > report.stat().st_mtime_ns
	intake = json.loads((WORK/'runtime/native-current/pm-next-intake.json').read_text())
	assert intake['published'] and intake['milestone_id'] == 'ASTRA-SELFHOST-27B-OWNERSHIP-AND-SYNTAX'
	sys.path.insert(0, str(Path.home()/'.agents/skills/pm-next/scripts'))
	from common import verify_zip
	manifest, digest = verify_zip(report, 'pm-codex-report/1')
	assert intake['report_sha256'] == digest and intake['report_path'] == str(report)
	head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip()
	tree = subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=ROOT).decode().strip()
	assert intake['final_commit'] == head and intake['final_tree'] == tree
	assert not subprocess.check_output(['git', 'status', '--porcelain=v1', '--untracked-files=no'], cwd=ROOT).strip()
	audit = json.loads((a.audit/'result.json').read_text())
	assert audit['HEAD'] == head and audit['tree'] == tree and audit['gates']['G5'] == 'PENDING_SEPARATE_AFTER_PUBLICATION_CHECK'
	write(runtime/'start.json', dict(UTC_ns=started, UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), report_sha256=digest, audit_sha256=sha(a.audit/'result.json'), HEAD=head, tree=tree, recipe_sha256=sha(__file__)))
	sources = {}
	with zipfile.ZipFile(report) as packed:
		result = json.loads(packed.read('RESULT.json'))
		assert result['status'] in ('PASS', 'PARTIAL') and result['final_commit'] == head and result['final_tree'] == tree
		engineering_status = result['status']
		assert result['submission_sha256'] == '6795f505907c8f19f25aee05f2677b33f6fa1d30344314507fdcee88340bc455'
		for name in packed.namelist():
			if not name.startswith('source/'): continue
			path = name[7:]; raw = packed.read(name)
			assert raw == subprocess.check_output(['git', 'show', head+':'+path], cwd=ROOT) == (ROOT/path).read_bytes()
			sources[path] = dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), Git_blob=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest())
		assert set(sources) == set(result['changed_committed_paths']) and 'OMISSIONS.md' not in packed.namelist()
		index = json.loads(packed.read('evidence/INDEX.json'))
		for row in index['files']:
			raw = packed.read('evidence/'+row['path']); assert len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256']
		transport = json.loads(packed.read('evidence/transport.json')); archive_hash = hashlib.sha256(); count = 0
		for row in transport['segments']:
			raw = packed.read('evidence/'+row['path']); assert len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256']
			archive_hash.update(raw); count += len(raw)
		assert archive_hash.hexdigest() == transport['archive_sha256'] and count == transport['archive_bytes']
		assert packed.read('evidence/engineering-audit.json') == (a.audit/'result.json').read_bytes()
	stage = audit['stages']['stage2']; compiler = stage['product']
	assert sha(compiler['path']) == compiler['sha256']
	stage_runtime = Path(next(path for path in audit['receipts'] if json.loads(Path(path).read_text()).get('product') == compiler)).parent
	for row in json.loads((stage_runtime/'snapshot.json').read_text())['sources']:
		assert sha(row['input_path']) == row['sha256'] == sha(row['original_path'])
	link = stage_runtime/'link.json'
	c0 = audit['C0_rebuilt_identity']['product']; assert sha(c0['path']) == c0['sha256']
	base = ['--compiler', compiler['path'], '--compiler-sha256', compiler['sha256'], '--c0', c0['path'], '--c0-sha256', c0['sha256'], '--link', str(link)]
	env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', CCACHE_DISABLE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	commands = []
	for name, recipe, extra in [('modern', 'native.py', ['--feature', 'workload']), ('intrinsic', 'intrinsic.py', []), ('physical', 'physical.py', ['--case', 'error-descriptor-field'])]:
		arguments = base if name != 'physical' else base[:4]
		argv = [sys.executable, '-B', str(Path(__file__).with_name(recipe)), *arguments, '--build', str(build/name), '--runtime', str(runtime/name), *extra]
		result = execute(argv, runtime/(name+'-controller'), timeout=900, env=env)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result)
		commands.append(dict(name=name, argv=argv, result=result, fresh_receipt_sha256=sha(runtime/name/'result.json')))
		write(runtime/'commands.json', commands)
	assert sha(ROOT/'docs/selfhost-effects-25-abi-proposal.md') == 'd77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e'
	assert sha(report) == digest and sha(compiler['path']) == compiler['sha256']
	assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip() == head
	write(runtime/'result.json', dict(status='POST_DELIVERY_27B_G5_PASS', UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), verification_started_UTC_ns=started, publication_UTC=intake['published_utc'], report=dict(path=str(report), bytes=report.stat().st_size, sha256=digest, indexed_payloads=len(manifest['files'])), engineering_status=engineering_status, HEAD=head, tree=tree, sources=sources, transport_sha256=transport['archive_sha256'], actual_stage2=compiler, commands_sha256=sha(runtime/'commands.json'), limitation='Separate exact-delivery, live modern O0/O2, intrinsic C ABI, strict unsuppressed compiler/program memory and physical negative checks. The immutable engineering audit retains G5 PENDING. This does not upgrade a PARTIAL engineering report or claim Stage3/release.'))
	print('POST_DELIVERY_27B_G5_PASS', digest, flush=True)


if __name__ == '__main__': main()
