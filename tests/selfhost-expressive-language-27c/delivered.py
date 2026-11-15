#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Separate post-publication 27-C G7, using existing proof recipes."""
import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write
sys.path.insert(0, str(ROOT/'tests/selfhost-compiler-complete'))
from evidence import verify


def git(*arguments):
	return subprocess.check_output(['git', *arguments], cwd=ROOT)


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('audit', 'stage-runtime', 'component-runtime', 'oracle-inputs', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	runtime = output_path(a.runtime, WORK/'runtime'); build = output_path(a.build, WORK/'build')
	runtime.mkdir(parents=True, exist_ok=False); build.mkdir(parents=True, exist_ok=False)
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	started = time.time_ns(); assert started > report.stat().st_mtime_ns
	intake = json.loads((WORK/'runtime/native-current/pm-next-intake.json').read_text())
	assert intake['published'] and intake['milestone_id'] == 'ASTRA-SELFHOST-27C-EXPRESSIVE-LANGUAGE'
	sys.path.insert(0, str(Path.home()/'.agents/skills/pm-next/scripts'))
	from common import verify_zip
	manifest, digest = verify_zip(report, 'pm-codex-report/1')
	assert intake['report_sha256'] == digest and intake['report_path'] == str(report)
	head = git('rev-parse', 'HEAD').decode().strip(); tree = git('rev-parse', 'HEAD^{tree}').decode().strip()
	assert intake['final_commit'] == head and intake['final_tree'] == tree
	assert not git('status', '--porcelain=v1', '--untracked-files=no').strip()
	audit = json.loads(a.audit.read_text())
	assert audit['HEAD'] == head and audit['tree'] == tree
	assert audit['gates']['G7'] == 'PENDING_SEPARATE_AFTER_PUBLICATION_CHECK'
	write(runtime/'start.json', dict(UTC_ns=started, UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), report_sha256=digest, audit_sha256=sha(a.audit), HEAD=head, tree=tree, recipe_sha256=sha(__file__)))
	sources = {}; archive = runtime/'published-transport.tar.xz'
	with zipfile.ZipFile(report) as packed:
		result = json.loads(packed.read('RESULT.json'))
		assert result['status'] == 'PASS' and result['final_commit'] == head and result['final_tree'] == tree
		assert result['submission_sha256'] == 'ec80c9c284fcc324f1f54837f4c7d2b028a98ae2980f4841c960576b4ecf4ab2'
		for name in packed.namelist():
			if not name.startswith('source/'): continue
			path = name[7:]; raw = packed.read(name)
			assert raw == git('show', head+':'+path) == (ROOT/path).read_bytes()
			sources[path] = dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest())
		index = json.loads(packed.read('evidence/INDEX.json'))
		for row in index['files']:
			raw = packed.read('evidence/'+row['path'])
			assert len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256']
		transport = json.loads(packed.read('evidence/transport.json'))
		with archive.open('xb') as out:
			for row in transport['segments']:
				raw = packed.read('evidence/'+row['path'])
				assert len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256']
				out.write(raw)
		assert archive.stat().st_size == transport['archive_bytes'] and sha(archive) == transport['archive_sha256']
		assert packed.read('evidence/engineering-audit.json') == a.audit.read_bytes()
	reconstruction = verify(archive, runtime); assert reconstruction['status'] == 'BYTE_EXACT'
	write(runtime/'reconstruction.json', reconstruction)
	with tarfile.open(archive, 'r|xz') as packed:
		model = None
		for member in packed:
			if member.name == 'INDEX.json': model = json.load(packed.extractfile(member))
	assert model is not None
	for path in result['changed_committed_paths']:
		row = model['files']['source/'+path]
		raw = git('show', head+':'+path)
		assert raw == (ROOT/path).read_bytes() and len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256']
		sources[path] = dict(bytes=len(raw), sha256=row['sha256'], Git_blob=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest())
	write(runtime/'source-delivery.json', sources)
	stage = json.loads((a.stage_runtime/'result.json').read_text()); compiler = stage['product']
	assert stage['producer']['kind'] == 'astra' and sha(compiler['path']) == compiler['sha256']
	for row in json.loads((a.stage_runtime/'snapshot.json').read_text())['sources']:
		assert sha(row['input_path']) == row['sha256'] == sha(row['original_path'])
	component = json.loads((a.component_runtime/'result.json').read_text())
	consumer = component['products']['O0']; assert sha(consumer['path']) == consumer['sha256']
	identity = json.loads((a.component_runtime/'identity.json').read_text())
	assert sha(a.component_runtime/'identity.json') == component['identity_sha256']
	for group in ('sources', 'actual_sources', 'providers', 'tools'):
		for path, value in identity[group].items(): assert sha(path) == value
	c0 = WORK/'build/selfhost27b/c0-recovery-safealloc2/astrac'
	assert sha(c0) == '19d744c828551b2184f06552740db1beb5b6eeb326b8e98ba56d2dfa5bca31b6'
	base = ['--compiler', compiler['path'], '--compiler-sha256', compiler['sha256'], '--c0', str(c0), '--c0-sha256', sha(c0), '--link', str(a.stage_runtime/'link.json')]
	env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', CCACHE_DISABLE='1')
	env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None)
	commands = []
	for name, recipe, extra in [
		('range', 'named.py', [*base, '--oracle-library-inputs', str(a.oracle_inputs), '--feature', 'range', '--case', 'range-collect-literal', '--case', 'range-stride']),
		('match', 'named.py', [*base, '--oracle-library-inputs', str(a.oracle_inputs), '--feature', 'match']),
		('physical', 'physical.py', [*base[:4], '--feature', 'range']),
	]:
		argv = [sys.executable, '-B', str(Path(__file__).with_name(recipe)), *extra, '--build', str(build/name), '--runtime', str(runtime/name)]
		outcome = execute(argv, runtime/(name+'-controller'), timeout=900, env=env)
		assert outcome['status'] == 'EXPECTED_OUTCOME', (name, outcome)
		commands.append(dict(name=name, argv=argv, result=outcome, fresh_receipt_sha256=sha(runtime/name/'result.json')))
		write(runtime/'commands.json', commands)
	for name, argv in [
		('source-owner-native', [consumer['path']]),
		('source-owner-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', consumer['path']]),
	]:
		outcome = execute(argv, runtime/name, expected=42, timeout=300, env=env)
		assert outcome['status'] == 'EXPECTED_OUTCOME', (name, outcome)
		assert b'MEMBER_DISPATCH_SOURCE_AND_CONSUMER_CONTROLS_PASS' in (runtime/name/'stdout').read_bytes()
		if name.endswith('memory'):
			log = (runtime/name/'stderr').read_bytes()
			assert all(marker in log for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		commands.append(dict(name=name, argv=argv, result=outcome)); write(runtime/'commands.json', commands)
	assert sha(ROOT/'docs/selfhost-effects-25-abi-proposal.md') == 'd77c02f3144ab5dc3da41eb310b29cd02629b49876042934ea5071a1549ac66e'
	assert sha(report) == digest and sha(compiler['path']) == compiler['sha256'] and git('rev-parse', 'HEAD').decode().strip() == head
	write(runtime/'result.json', dict(status='POST_DELIVERY_27C_G7_PASS', UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), verification_started_UTC_ns=started, publication_UTC=intake['published_utc'], report=dict(path=str(report), bytes=report.stat().st_size, sha256=digest, indexed_payloads=len(manifest['files'])), HEAD=head, tree=tree, source_paths=len(sources), transport_sha256=transport['archive_sha256'], actual_stage2=compiler, source_owner_consumer=consumer, commands_sha256=sha(runtime/'commands.json'), limitation='Separate actual after-publication Stage2 O0/O2 compilation/execution, strict returning compiler/target memory, source/owner and LLVM-valid physical refusals. Immutable prepublication G7 remains PENDING. Prior27B PARTIAL and historical loss remain unchanged; no Stage3 or release credit.'))
	print('POST_DELIVERY_27C_G7_PASS', digest, flush=True)


if __name__ == '__main__':
	main()
