#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Separate G7: verify the installed delivery, then execute its real Stage2.

Run only after publication. This receipt deliberately lives outside the ZIP
whose exact delivered bytes it verifies; no circular prepublication G7 claim.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, '/home/pmjobin/.agents/skills/pm-next/scripts')
from common import verify_zip
sys.path.insert(0, str(ROOT/'tests/selfhost-compiler-complete'))
from run import WORK, git, sha
from acceleration import environment, execute, output_path, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for n in ('inputs', 'audit', 'runtime', 'build'): p.add_argument('--'+n, type=Path, required=True)
	p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	leaf = output_path(a.runtime/a.version, WORK/'runtime'); build = output_path(a.build/a.version, WORK/'build')
	leaf.mkdir(); build.mkdir()
	report = ROOT.parent/'codex/reports/astra-report-current.zip'
	intake_path = WORK/'runtime/native-current/pm-next-intake.json'; intake = json.loads(intake_path.read_text())
	started = time.time_ns(); assert started > report.stat().st_mtime_ns
	write(leaf/'start.json', dict(UTC_ns=started, UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), report=str(report), report_sha256=sha(report), script_sha256=sha(__file__)))
	manifest, report_hash = verify_zip(report, 'pm-codex-report/1')
	assert intake['published'] and intake['report_sha256'] == report_hash and intake['report_path'] == str(report)
	assert intake['milestone_id'] == 'ASTRA-SELFHOST-27A-INITIAL-BOOTSTRAP'
	head = git('rev-parse', 'HEAD').decode().strip(); tree = git('rev-parse', 'HEAD^{tree}').decode().strip()
	assert intake['final_commit'] == head and intake['final_tree'] == tree
	assert not git('diff', '--name-only').strip() and not git('diff', '--cached', '--name-only').strip()
	sources = {}
	with zipfile.ZipFile(report) as packed:
		result = json.loads(packed.read('RESULT.json'))
		assert result['status'] == 'PASS' and result['final_commit'] == head and result['final_tree'] == tree
		assert result['submission_sha256'] == '5f347d59b807d08f4c488d5917869b0e2dfe33652ff995be11a48392fa5bd6a1'
		for name in packed.namelist():
			if name.startswith('source/'):
				path = name[7:]; raw = packed.read(name)
				assert raw == git('show', head+':'+path) == (ROOT/path).read_bytes()
				sources[path] = dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), Git_blob=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest())
		assert set(sources) == set(result['changed_committed_paths']) and 'OMISSIONS.md' not in packed.namelist()
		evidence = json.loads(packed.read('evidence/INDEX.json'))
		for row in evidence['files']:
			raw = packed.read('evidence/'+row['path'])
			assert len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256']
		transport = json.loads(packed.read('evidence/transport.json')); digest = hashlib.sha256(); size = 0
		for row in transport['segments']:
			raw = packed.read('evidence/'+row['path']); assert len(raw) == row['bytes'] and hashlib.sha256(raw).hexdigest() == row['sha256']
			digest.update(raw); size += len(raw)
		assert digest.hexdigest() == transport['archive_sha256'] and size == transport['archive_bytes']
		accepted = json.loads(packed.read('evidence/engineering-audit.json'))
		assert packed.read('evidence/engineering-audit.json') == (a.audit/'result.json').read_bytes()
		assert accepted['status'] == 'BOUNDED_27A_ENGINEERING_PASS' and accepted['HEAD'] == head and accepted['tree'] == tree
		assert accepted['gates']['G7']['status'] == 'PENDING' and not accepted['full_milestone27_credit'] and not accepted['release_credit']
	plan = json.loads((a.inputs/'ownflow-O2-input-identity.json').read_text())
	assert all(sha(path) == h for path, h in plan['tools'].items())
	inputs = json.loads((a.inputs/'inputs.json').read_text())['inputs']
	assert len(inputs) == 206 and all(sha(path) == h for path, h in inputs.items())
	for row in json.loads((a.inputs/'snapshot.json').read_text())['sources']:
		assert sha(row['input_path']) == row['sha256'] == sha(row['original_path'])
	stage = accepted['stages']['stage2']['O2']; producer = Path(stage['path'])
	assert sha(producer) == stage['sha256'] and producer.read_bytes()[:4] == b'\x7fELF'
	fixture = ROOT/'tests/selfhost-bootstrap-27a/caught-message-scalars.astra'
	assert fixture.read_bytes() == git('show', head+':'+str(fixture.relative_to(ROOT)))
	program = {str(fixture):sha(fixture), **{path:h for path, h in inputs.items() if path.endswith(('/lib/astra/base/errors.astra', '/lib/astra/hosted/text.astra'))}}
	link = json.loads((a.inputs/'link.json').read_text()); assert all(sha(path) == h for path, h in link['objects'].items())
	providers = [path for path in link['objects'] if Path(path).name not in ('llvm-capi.o', 'arguments.o')]
	env = environment(dict(LD_PRELOAD=None, VALGRIND_OPTS=None, CCACHE_DISABLE='1')); commands = []
	def run(name, argv, expected=0):
		argv = list(map(str, argv)); observed = execute(argv, leaf/name, expected=expected, timeout=300, env=env)
		commands.append(dict(name=name, argv=argv, observation=observed)); write(leaf/'commands.json', commands)
		assert observed['status'] == 'EXPECTED_OUTCOME', (name, observed)
	def memory(name, argv, expected):
		run(name, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv], expected)
		log = (leaf/name/'stderr').read_bytes()
		assert all(x in log for x in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	ir = build/'post-delivery.ll'; obj = build/'post-delivery.o'; exe = build/'post-delivery-native'
	memory('compiler-memory', [producer, '--emit-llvm', '-o', ir, *program], 0)
	run('LLVM-verify', ['opt', '-passes=verify', '-disable-output', ir])
	run('native-object', ['llc', '-filetype=obj', '-O2', ir, '-o', obj])
	run('native-link', ['cc', '-no-pie', obj, *providers, '-o', exe])
	run('native-execute', [exe], 42)
	assert (leaf/'native-execute/stderr').read_bytes() == b'copied results\n'
	memory('native-memory', [exe], 42)
	assert all(sha(path) == h for path, h in program.items()) and sha(producer) == stage['sha256']
	assert sha(report) == report_hash and git('rev-parse', 'HEAD').decode().strip() == head
	write(leaf/'result.json', dict(status='POST_DELIVERY_G7_PASS', UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), verification_started_UTC_ns=started, installed_publication_UTC=intake['published_utc'], report=dict(path=str(report), sha256=report_hash, bytes=report.stat().st_size, indexed_payloads=len(manifest['files'])), HEAD=head, tree=tree, source_Git_blobs=sources, transport_sha256=transport['archive_sha256'], actual_stage2=stage, fresh_program_inputs=program, fresh_products={str(path):sha(path) for path in (ir, obj, exe)}, command_receipt_sha256=sha(leaf/'commands.json'), limitation='Separate after-delivery ZIP/live-source/product and strict returning native replay. The immutable report correctly retains G7 PENDING at its earlier audit creation. No full 27-D convergence or release credit.'))
	print('POST_DELIVERY_G7_PASS', report_hash, flush=True)


if __name__ == '__main__':
	main()
