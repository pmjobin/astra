#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Separately dated live checks bound to the actual canonical published ZIP."""
import argparse
import datetime
import json
import os
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write
from audit import preservation


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('report', 'qualification', 'toolchain', 'runtime', 'build'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--report-sha256', required=True)
	a = p.parse_args()
	assert a.report == ROOT.parent/'codex/reports/astra-report-current.zip'
	assert sha(a.report) == a.report_sha256
	with zipfile.ZipFile(a.report) as z:
		report = json.loads(z.read('RESULT.json'))
		manifest = json.loads(z.read('MANIFEST.json'))
		assert report['project_id'] == 'astra' and report['milestone_id'] == 'ASTRA-RELEASE-28A1-API-DOCUMENTATION'
		assert manifest['submission_sha256'] == report['submission_sha256'] == '744f720a876d67ec3e10568c1e0f6494dc962df9d0cef256528e09c0f5348cf9'
	assert report['final_commit'] == subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True, cwd=ROOT).strip()
	assert report['final_tree'] == subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], text=True, cwd=ROOT).strip()
	assert not subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT).strip()
	start = datetime.datetime.now(datetime.timezone.utc)
	assert start > datetime.datetime.fromisoformat(report['timestamp'])
	qualification = json.loads(a.qualification.read_text())
	products_path = Path(qualification['products_manifest']['path'])
	assert sha(products_path) == qualification['products_manifest']['sha256']
	products = json.loads(products_path.read_text())['products']
	assert set(products) == {'O0', 'O2'}
	for row in qualification['receipts'].values(): assert sha(row['path']) == row['sha256']
	for product in products.values():
		assert sha(product['path']) == product['sha256']
		assert all(sha(product[kind]['path']) == product[kind]['sha256'] for kind in ('native', 'doc'))
	runtime = output_path(a.runtime, WORK/'runtime')
	build = output_path(a.build, WORK/'build')
	runtime.mkdir(parents=True, exist_ok=False)
	build.mkdir(parents=True, exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	write(runtime/'start.json', dict(start_UTC=start.isoformat(), report_sha256=a.report_sha256, publication_UTC=report['timestamp'], report_commit=report['final_commit'], qualification_sha256=sha(a.qualification), scope='After local canonical publication; no claim that a human has uploaded the ZIP elsewhere'))
	toolchain = json.loads(a.toolchain.read_text())
	assert all(sha(path) == value for path,value in toolchain['tools'].items())
	env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
	env.update({key:value for key,value in toolchain['environment'].items() if value is not None})
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	commands = []
	def run(label, argv, expected=0):
		result = execute(argv, runtime/label, expected=expected, timeout=900, env=env)
		commands.append(dict(label=label, argv=list(map(str, argv)), result=result))
		write(runtime/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', label
		print(label, result['status'], round(result['seconds'], 3), flush=True)
	run('native-replay', ['python3', '-B', ROOT/'tests/api-docs/native.py', '--products', products_path, '--toolchain', a.toolchain, '--runtime', runtime/'native', '--build', build/'native'])
	assert json.loads((runtime/'native/result.json').read_text())['status'] == 'CURRENT_COMPLETE_COMPILER_DOCS_ISOLATION_AND_COMMENT_EQUIVALENCE_PASS'
	for mode,product in products.items():
		identity = WORK/('runtime/api-docs28a1-bundle-'+mode+'/docs-build-identity.json')
		run(mode+'-focused-replay', ['python3', '-B', ROOT/'tests/api-docs/run.py', '--compiler', product['path'], '--compiler-sha256', product['sha256'], '--toolchain', a.toolchain, '--build-identity', identity, '--runtime', runtime/(mode+'-focused')])
		assert json.loads((runtime/(mode+'-focused/result.json')).read_text())['status'] == 'FOCUSED_NATIVE_DOCS_ACCEPTANCE_PASS'
	source_receipt = qualification['receipts']['source-owner']
	source = json.loads(Path(source_receipt['path']).read_text())
	assert source['status'] == 'FOCUSED_EXPRESSIVE_SEMANTIC_COMPONENT_PASS'
	for mode,product in source['products'].items():
		assert sha(product['path']) == product['sha256']
		label = mode+'-source-owner-memory-replay'
		run(label, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product['path']], expected=42)
		assert all(marker in (runtime/label/'stderr').read_bytes() for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	preserved = preservation(WORK/'runtime/selfhost27b-intake/pre-edit-preservation.json')
	assert sha(a.report) == a.report_sha256
	write(runtime/'result.json', dict(status='AFTER_CANONICAL_PUBLICATION_28A1_LIVE_REPLAY_PASS', start_UTC=start.isoformat(), completed_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), report_sha256=a.report_sha256, final_commit=report['final_commit'], qualification_sha256=sha(a.qualification), commands_sha256=sha(runtime/'commands.json'), preservation=preserved, scope='Genuine subsequent local checks: both compiler profiles, live O0/O2 compilation/execution, LLVM isolation/guard controls, strict documentation negatives and unsuppressed all-kinds source-owner execution. Prior physical mutation suites are authenticated by the bound qualification receipts, not relabeled as newly executed here. Immutable published ZIP remains unchanged.'))


if __name__ == '__main__':
	main()
