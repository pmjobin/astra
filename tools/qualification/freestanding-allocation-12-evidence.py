# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Verify current Surge 12 receipts and write a compact, portable report inventory."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import stat
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def digest(data):
	return hashlib.sha256(data).hexdigest()


def identity(path):
	path = Path(path).resolve()
	data = path.read_bytes()
	return dict(path=str(path), bytes=len(data), sha256=digest(data))


def git(*arguments, cwd=ROOT):
	return subprocess.check_output(['git', *arguments], cwd=cwd).decode()


def compact(value):
	if isinstance(value, str) and len(value) > 2048:
		return dict(bytes=len(value.encode()), sha256=digest(value.encode()),
			prefix=value[:640], suffix=value[-256:])
	if isinstance(value, dict):
		return {key: compact(item) for key, item in value.items()}
	if isinstance(value, list):
		return [compact(item) for item in value]
	return value


def same_file(path, recorded):
	info = identity(path)
	assert info['sha256'] == recorded['sha256'], (path, 'content changed')
	assert info['bytes'] == recorded.get('bytes', recorded.get('size')), path
	if 'mode' in recorded:
		assert oct(stat.S_IMODE(Path(path).stat().st_mode)) == recorded['mode'], path
	return info


def conservation(stage):
	initial = json.loads((stage / 'intake-preservation.json').read_text())
	assert not initial['dirty_tracked'], 'this recipe expects the recorded clean tracked intake'
	assert not git('diff', '--cached', '--name-only'), 'index must be empty'
	untracked = set(git('ls-files', '--others', '--exclude-standard', '-z').split('\0'))
	files = []
	for row in initial['untracked']:
		assert row['path'] in untracked, ('initial user file was tracked/removed', row['path'])
		files.append(same_file(ROOT / row['path'], row))
	hooks = Path(git('rev-parse', '--git-path', 'hooks').strip())
	if not hooks.is_absolute():
		hooks = ROOT / hooks
	assert {p.name for p in hooks.iterdir() if p.is_file()} == {r['path'] for r in initial['hooks']}
	for row in initial['hooks']:
		same_file(hooks / row['path'], row)
	active = 'refs/heads/' + initial['branch']
	def other_refs(text):
		return sorted(line for line in text.splitlines() if line.split()[-1] != active)
	assert other_refs(git('show-ref')) == other_refs(initial['refs'])
	assert git('stash', 'list', '--format=%H %gd %s') == initial['stash']
	peer = ROOT.parent / 'aster-scale/compiler/astra'
	assert git('rev-parse', 'HEAD', cwd=peer).strip() == initial['peer_head']
	assert git('status', '--porcelain=v1', '--untracked-files=all', cwd=peer) == initial['peer_status']
	ignored = git('ls-files', '--others', '--ignored', '--exclude-standard', '-z').strip('\0').split('\0')
	assert [x for x in ignored if x] == initial['ignored']
	return dict(status='PASS', intake=identity(stage / 'intake-preservation.json'),
		user_files=files, hook_files=len(initial['hooks']), other_refs_sha256=digest('\n'.join(other_refs(initial['refs'])).encode()),
		stash=initial['stash'], peer_head=initial['peer_head'], peer_status=initial['peer_status'], ignored=initial['ignored'])


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--build', type=Path, required=True)
	parser.add_argument('--stage', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	args = parser.parse_args()
	build, stage = args.build.resolve(), args.stage.resolve()
	assert not build.is_relative_to(ROOT) and not stage.is_relative_to(ROOT)
	compiler = identity(build / 'astrac')
	initial = json.loads((stage / 'intake-preservation.json').read_text())
	source_paths = git('diff', '--name-only', initial['head'], 'HEAD').splitlines()
	sources = []
	for path in source_paths:
		if (ROOT / path).is_file():
			assert not git('diff', 'HEAD', '--', path), ('source changed after checkpoint', path)
			sources.append(dict(relative_path=path, git_blob=git('rev-parse', 'HEAD:' + path).strip(), **identity(ROOT / path)))
	receipts = []
	root = build / 'tests/freestanding-allocation-12'
	paths = [root / folder / (name + '.json') for folder, name in [
		('guest', 'guest-foundation'), ('devices', 'guest-devices'),
		('owners', 'allocation-owners'), ('policies', 'guest-policies'),
		('refusals', 'allocation-refusals'), ('modules', 'allocation-modules'),
		('sanitizers', 'allocation-sanitizers'), ('substrate', 'allocation-substrate'),
		('packet-checked', 'packet-checked')]]
	paths += [stage / 'regressions/surge-12-regressions.json', stage / 'metrics/allocation-costs.json']
	for path in paths:
		document = json.loads(path.read_text())
		assert document['status'] == 'PASS', path
		assert document['compiler'] == compiler, (path, 'stale compiler')
		for command in document['commands']:
			assert command['exit'] == command['expected_exit'], (path, command)
			if command.get('expected_stdout') is not None:
				assert command['stdout'] == command['expected_stdout'], path
			if command.get('required_text') is not None:
				assert command['required_text'] in command['stdout'] + command['stderr'], path
		for row in document['files']:
			same_file(row['path'], row)
		receipts.append(dict(receipt=identity(path), evidence=compact(document)))
	timer_path = root / 'timer-continuity/results.json'
	timer = json.loads(timer_path.read_text())
	assert timer['status'] == 'PASS' and timer['compiler_sha256'] == compiler['sha256']
	assert len(timer['commands']) == 11 and all(c['passed'] for c in timer['commands'])
	for path, sha in timer['sources'].items():
		assert identity(ROOT / path)['sha256'] == sha, path
	assert identity(timer['liburing']['archive'])['sha256'] == timer['liburing']['archive_sha256']
	assert identity(timer['generated']['receipt'])['sha256'] == timer['generated']['sha256']
	meson_path = build / 'meson-logs/surge-12-final-selection.json'
	tests = [json.loads(line) for line in meson_path.read_text().splitlines()]
	selection = (ROOT / 'tests/freestanding-allocation-12/regression-selection.txt').read_text().splitlines()
	assert len(tests) == len(selection) == 156
	assert all(t['result'] == 'OK' for t in tests)
	assert {t['name'].split(':')[-1] for t in tests} == set(selection)
	probe = json.loads((stage / 'target-probe.json').read_text())
	for tool in probe['tools'].values():
		if tool.get('found'):
			same_file(tool['executable']['path'], tool['executable'])
	firmware = next(row for row in probe['firmware'] if row['path'] == '/usr/share/seabios/bios-256k.bin')
	same_file(firmware['path'], firmware)
	baseline_metadata = json.loads((stage / 'baseline-compiler.json').read_text())
	baseline_commands = json.loads((stage / 'baseline-commands.json').read_text())
	assert baseline_metadata['head'] == initial['head']
	assert all(c['returncode'] == 0 for c in baseline_commands)
	baseline_compiler = identity(build / 'astrac-surge-12-baseline')
	assert baseline_compiler['sha256'] == baseline_metadata['sha256']
	baseline_tests_path = build / 'meson-logs/surge-12-baseline.json'
	baseline_tests = [json.loads(line) for line in baseline_tests_path.read_text().splitlines()]
	assert len(baseline_tests) == 69 and all(t['result'] == 'OK' for t in baseline_tests)
	configuration = json.loads(subprocess.check_output(['meson', 'introspect', str(build), '--buildoptions']))
	options = {item['name']: item['value'] for item in configuration}
	assert options['werror'] is True and options['linux_async'] is False
	result = dict(format='astra-freestanding-allocation-12-evidence/1',
		created_utc=datetime.now(timezone.utc).isoformat(), status='PASS',
		base_commit=initial['head'], source_checkpoint=git('rev-parse', 'HEAD').strip(),
		compiler=compiler, source_files=sources, build_options=options,
		baseline=dict(status='PASS', scope='Historical pre-edit baseline only',
		metadata=baseline_metadata, compiler=baseline_compiler, selected=69,
		commands=baseline_commands, test_receipt=identity(baseline_tests_path),
		logs=[identity(stage / name) for name in ('baseline-configure.log', 'baseline-build.log', 'baseline-tests.log')]),
		target=dict(triple='x86_64-none-elf', machine='pc-i440fx-10.2', accelerator='tcg',
		cpu='qemu64', ram_mib=64, firmware=firmware,
		approval='User explicitly approved this discovered x86-64 PC target in the native session; actual guest commands/outputs are in the current receipts.',
		probe=identity(stage / 'target-probe.json'), host=probe['host'],
		tools=compact(probe['tools'])),
		meson=dict(receipt=identity(meson_path), selected=len(tests), passed=len(tests),
		tap_assertions=sum(len(re.findall(r'^ok\s+\d+\b', t.get('stdout', ''), re.M)) for t in tests),
		tests=[compact(t) for t in tests]),
		receipts=receipts, timer=dict(receipt=identity(timer_path), evidence=compact(timer)),
		conservation=conservation(stage),
		limits='Selected emulated target and 156 registrations only. No physical silicon, peak stack-pointer measurement, full registry, SH-4, self-hosting, threaded Shared, general frame placement or historical LAZY-1 Q4 acceptance. ASan instruments eligible emitted host Astra and authored C; UBSan covers authored C. Guest memory uses explicit bounds, counters, layout and startup guards. Complete raw logs remain at the identified external paths; this file retains exact short output and hashes plus excerpts for large output.')
	args.output.write_text(json.dumps(result, indent=2) + '\n')
	assert args.output.stat().st_size <= 2 * 1024 * 1024, 'publisher per-file cap'
	print('PASS:', len(sources), 'source identities;', len(receipts), 'current receipts;', len(tests), 'tests;', result['meson']['tap_assertions'], 'TAP assertions')


if __name__ == '__main__':
	main()
