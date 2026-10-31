# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Create a compact, source-checked index of the actual final receipts."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tests/systems-dsp-9'))
from support import identity


def main(build, output):
	build, output = Path(build).resolve(), Path(output).resolve()
	compiler = identity(build / 'astrac')
	selection = build / 'concurrency-runtime-13/final-selection/concurrency-final-selection.json'
	campaign = json.loads(selection.read_text())
	assert campaign['status'] == 'PASS' and campaign['compiler'] == compiler
	log = build / 'meson-logs/concurrency-runtime-13-final.json'
	rows = [json.loads(line) for line in log.read_text().splitlines()]
	assert {row['name'].split(':', 1)[-1] for row in rows} == set(campaign['selection'])
	assert len(rows) == 53 and all(row['result'] == 'OK' and row['returncode'] == 0 for row in rows)
	historical_receipts = []
	for row in rows:
		if ':concurrency-runtime-13-' in row['name']: continue
		for argument in row['command']:
			directory = Path(argument)
			if not directory.is_absolute() or not directory.is_relative_to(build) or not directory.is_dir(): continue
			for path in sorted(directory.rglob('*.json')):
				if path.stat().st_mtime < row['starttime']: continue
				try: data = json.loads(path.read_text())
				except (ValueError, UnicodeError): continue
				if not isinstance(data, dict): continue
				pin = data.get('compiler_sha256')
				if isinstance(data.get('compiler'), dict): pin = data['compiler'].get('sha256')
				if pin != compiler['sha256']: continue
				historical_receipts.append(dict(**identity(path), registration=row['name'], embedded_status=data.get('status'), commands=len(data.get('commands', data.get('checks', data.get('records', []))))))
	current = sorted((build / 'tests/concurrency-runtime-13').glob('*/concurrency-*.json'))
	assert len(current) == 20
	paths = [selection, *current,
		build / 'concurrency-runtime-13/image-tiles/concurrency-image-tiles.json',
		build / 'concurrency-runtime-13/metrics/concurrency-costs.json']
	receipts = []
	for path in paths:
		data = json.loads(path.read_text())
		assert data['status'] == 'PASS' and data['compiler'] == compiler, path
		for row in data.get('files', []):
			if Path(row['path']).is_relative_to(ROOT):
				assert identity(row['path']) == row, 'receipt source changed: ' + row['path']
		receipts.append(dict(**identity(path), name=data['name'], commands=len(data['commands']), status='PASS'))
	timer = selection.parent / 'timer/results.json'
	data = json.loads(timer.read_text())
	assert data['status'] == 'PASS' and data['compiler_sha256'] == compiler['sha256']
	receipts.append(dict(**identity(timer), name='real-liburing-timer', commands=len(data['commands']), status='PASS'))
	apps = json.loads((build / 'tests/concurrency-runtime-13/applications/concurrency-applications.json').read_text())
	assert set(apps['applications']) == {f'A{n}' for n in range(109, 121)}
	assert all(app['status'] == 'PASS' and app['levels'] == ['O0', 'O1', 'O2'] for app in apps['applications'].values())
	paths = subprocess.check_output(['git', '-C', ROOT, 'ls-files', '-co', '--exclude-standard', '-z',
		'bootstrap', 'lib', 'tests/concurrency-runtime-13', 'examples/concurrency-runtime-13', 'tests/shared-1b', 'meson.build', 'meson.options']).decode().split('\0')
	inventory = []
	for name in sorted(set(paths) - {''}):
		path = ROOT / name
		if path.is_file() and '__pycache__' not in path.parts and path.suffix != '.md':
			row = identity(path); row['path'] = name; inventory.append(row)
	canonical = json.dumps(inventory, sort_keys=True, separators=(',', ':')).encode()
	metrics = json.loads((build / 'concurrency-runtime-13/metrics/concurrency-costs.json').read_text())
	preservation = ROOT.parent / 'codex/work/astra/runtime/native-current/preservation-before-commit.json'
	assert json.loads(preservation.read_text())['status'] == 'PASS'
	result = dict(format='astra-concurrency-evidence/1', status='PASS',
		task='ASTRA-CONCURRENCY-RUNTIME-SURGE-13', tested_base='082b28f7cc56616084f15090d4d9f88bc07ed8b1',
		submission=dict(filename='ASTRA-CONCURRENCY-RUNTIME-SURGE-13-SUBMISSION.zip', sha256='7b0b4af408eae7e2f83bf5220c8d0e4d200911ffc148c9c4ddb09c98d54508fb'),
		compiler=compiler, source_inventory_sha256=hashlib.sha256(canonical).hexdigest(), source_inventory=inventory,
		registrations=[dict(name=row['name'], result=row['result'], returncode=row['returncode'], seconds=row['duration'], command=row['command'], entry_identity=identity(row['command'][0]) if Path(row['command'][0]).is_relative_to(build) else None, stdout_sha256=hashlib.sha256(row['stdout'].encode()).hexdigest()) for row in rows],
		raw_log=identity(log), receipts=receipts, historical_receipts=historical_receipts, applications=apps['applications'],
		costs={key: metrics[key] for key in ['provider_layouts', 'measurements', 'unique', 'guest']},
		preservation=identity(preservation), optional_provider_build=identity(ROOT.parent / 'codex/work/astra/runtime/native-current/optional-provider-build.log'),
		application_text_equivalence=identity(ROOT.parent / 'codex/work/astra/runtime/native-current/application-eof-equivalence.json'), limitations=[
		'Finite GNU Linux x86-64 execution; stress and sanitizers do not prove universal race freedom.',
		'Actual QEMU no-OS preservation; no physical-board, SH-4 or self-hosting claim.',
		'Explicit selected historical intersection; no full registry or all A01-A108 claim.',
		'Bounded exact C thread-carrier callbacks; ordinary retained registrar remains single threaded.',
		'No general COM/GObject export, foreign agility, ordered multi-monitor API or cycle collection.',
		'Historical LAZY-1 Q4 remains HELD/INCOMPLETE.'])
	output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
	print(f'PASS: compact evidence: {len(rows)} registrations, {len(receipts)} receipts, twelve applications; {len(inventory)} source identities')


if __name__ == '__main__':
	main(*sys.argv[1:])
