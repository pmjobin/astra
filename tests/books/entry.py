#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Reauthenticate the actual 28-A1 delivery gate before book engineering."""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import output_path, sha, write
from audit import preservation


def authenticate():
	archive = ROOT.parent/'codex/submissions/ASTRA-RELEASE-28A2-LANGUAGE-REFERENCE-AND-GUIDE-SUBMISSION.zip'
	assert archive.stat().st_size == 51306544 and sha(archive) == '641e588a2e2e17a0772fe15d66bb1907ad2f1da111a7083e937f072d664e0ed2'
	with zipfile.ZipFile(archive) as z:
		# This inspected standard-library verifier only reads archive bytes.
		module = {'__name__':'reviewed_offline_verifier', '__file__':str(archive)}
		exec(compile(z.read('VERIFY-OFFLINE.py'), 'VERIFY-OFFLINE.py', 'exec'), module)
		offline = module['verify'](archive)
		for name in z.namelist():
			if name.startswith('reference/report28a1/source/'):
				path = name.removeprefix('reference/report28a1/source/')
				assert subprocess.check_output(['git', 'show', '9f5dfce1a7dbaa8fba93e783762563add34a1948:'+path], cwd=ROOT) == z.read(name)
	report_path = ROOT.parent/'codex/reports/astra-report-current.zip'
	assert sha(report_path) == '1acc88af43839d90a52ec88b6ff4898e9305ffefd97988136ff28f8ceb40081f'
	with zipfile.ZipFile(report_path) as z:
		report = json.loads(z.read('RESULT.json'))
		qualification_bytes = z.read('evidence/QUALIFICATION.json')
	qualification = json.loads(qualification_bytes)
	directory = WORK/'runtime/api-docs28a1-after-publication2'
	receipt = json.loads((directory/'result.json').read_text())
	assert receipt['status'] == 'AFTER_CANONICAL_PUBLICATION_28A1_LIVE_REPLAY_PASS'
	assert receipt['report_sha256'] == sha(report_path)
	assert receipt['qualification_sha256'] == hashlib.sha256(qualification_bytes).hexdigest()
	assert datetime.datetime.fromisoformat(receipt['start_UTC']) > datetime.datetime.fromisoformat(report['timestamp'])
	assert datetime.datetime.fromisoformat(receipt['completed_UTC']) > datetime.datetime.fromisoformat(receipt['start_UTC'])
	assert (directory/'executed-recipe.py.txt').read_bytes() == (ROOT/'tests/api-docs/delivery.py').read_bytes()
	assert sha(directory/'commands.json') == receipt['commands_sha256']
	assert receipt['final_commit'] == report['final_commit'] == subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
	assert report['final_tree'] == subprocess.check_output(['git', 'rev-parse', 'HEAD^{tree}'], cwd=ROOT, text=True).strip()
	assert not subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT).strip()
	commands = strict = 0
	for path in directory.rglob('commands.json'):
		for row in json.loads(path.read_text()):
			label = row.get('label', row.get('name'))
			result = row.get('result', row)
			assert result['exit'] == result.get('expected_exit', result.get('expected'))
			assert not result.get('timed_out', False)
			for kind in ('stdout', 'stderr', 'time'):
				leaf = path.parent/label/('time.txt' if kind == 'time' else kind)
				if not leaf.is_file(): leaf = path.parent/(label+('.time' if kind == 'time' else '.'+kind))
				assert sha(leaf) == result[kind+'_sha256'], leaf
				if kind == 'stderr' and b'Memcheck, a memory error detector' in leaf.read_bytes():
					assert all(marker in leaf.read_bytes() for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)')), leaf
					strict += 1
			commands += 1
	for row in qualification['receipts'].values(): assert sha(row['path']) == row['sha256']
	product_path = Path(qualification['products_manifest']['path'])
	assert sha(product_path) == qualification['products_manifest']['sha256']
	for product in json.loads(product_path.read_text())['products'].values():
		for image in (product, product['native'], product['doc']): assert sha(image['path']) == image['sha256']
	toolchain_path = WORK/'runtime/selfhost27c-dev21/build-identity.json'
	toolchain = json.loads(toolchain_path.read_text())
	for path,digest in toolchain['tools'].items(): assert sha(path) == digest
	env = dict(__import__('os').environ)
	env.update({key:value for key,value in toolchain['environment'].items() if value is not None})
	assert subprocess.check_output(['llvm-config', '--version'], env=env).strip() == b'23.1.4'
	return dict(status='AUTHENTICATED_28A1_AFTER_PUBLICATION_G7_PASS', authenticated_UTC=datetime.datetime.now(datetime.timezone.utc).isoformat(), offline=offline, report_sha256=sha(report_path), publication_UTC=report['timestamp'], delivery=receipt, delivery_receipt_sha256=sha(directory/'result.json'), raw_commands=commands, strict_memory_streams=strict, qualification_receipts=len(qualification['receipts']), preservation=preservation(WORK/'runtime/selfhost27b-intake/pre-edit-preservation.json'), scope='Discovered genuine subsequent host execution, rehashed now. Physical/ABI suites are authenticated bound qualification evidence, not claimed freshly rerun by delivery.py. Original report is immutable; no lost historical proofs are restored.')


if __name__ == '__main__':
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	runtime = output_path(a.runtime, WORK/'runtime')
	result = authenticate()
	runtime.mkdir(parents=True, exist_ok=False)
	write(runtime/'entry.json', result)
	(runtime/'entry-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	print(result['status'])
