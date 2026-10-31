#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Audit own Meson contracts/results without executing tests or inheriting env data.

The pickle is trusted, task-generated Meson build metadata, never a submission or
downloaded file. Inventory/guard checks alone do not qualify registry execution.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import pickle
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	with path.open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def audit(contracts, results):
	names = [row['name'].removeprefix('astra:') for row in results]
	assert len(names) == len(set(names)) == len(contracts)
	assert set(names) == set(contracts)
	for name, row in zip(names, results):
		contract = contracts[name]
		assert row['result'] == 'OK' and not contract['expected_fail'], name
		assert row['returncode'] == contract['expected_exit'], name
		assert row['command'] == contract['argv'], name
		assert row['duration'] >= 0, name
		assert not any(re.match(r'^\s*(?:not )?ok\s+\d+.*#\s*SKIP\b', line, re.I) for line in row.get('stdout', '').splitlines()), name
		# Meson records start/duration in the same time.time domain. Its serial
		# scheduler waits for all prior futures, then awaits the serial future before
		# scheduling another. Require nonoverlap in the actual recorded intervals.
	for name, row in zip(names, results):
		if contracts[name]['is_parallel']: continue
		begin, end = row['starttime'], row['starttime'] + row['duration']
		for other_name, other in zip(names, results):
			if other_name == name: continue
			assert min(end, other['starttime'] + other['duration']) <= max(begin, other['starttime']), (name, other_name)


def guard_checks():
	contracts = {
		'refusal': dict(name='refusal', expected_exit=2, expected_fail=False, is_parallel=True, argv=['compiler', '--bad']),
		'parallel': dict(name='parallel', expected_exit=0, expected_fail=False, is_parallel=True, argv=['parallel']),
		'serial': dict(name='serial', expected_exit=0, expected_fail=False, is_parallel=False, argv=['serial']),
	}
	rows = [dict(name='astra:' + name, result='OK', returncode=contract['expected_exit'], command=contract['argv'],
		starttime=float(index if name != 'serial' else 3), duration=1.5 if name == 'refusal' else 1.0, stdout='ok 1\n')
		for index, (name, contract) in enumerate(contracts.items())]
	audit(contracts, rows)
	mutations = {
		'false-OK-wrong-exit': lambda r: r[0].update(returncode=0),
		'wrong-command': lambda r: r[0].update(command=['different']),
		'missing-name': lambda r: r.pop(),
		'duplicate-name': lambda r: r.__setitem__(1, r[0]),
		'unknown-name': lambda r: r[0].update(name='astra:unknown'),
		'failed-result': lambda r: r[0].update(result='TIMEOUT'),
		'skipped-TAP': lambda r: r[0].update(stdout='ok 1 # SKIP missing dependency\n'),
		'overlapping-serial': lambda r: r[2].update(starttime=1.4),
	}
	for name, mutate in mutations.items():
		changed = copy.deepcopy(rows); mutate(changed)
		try: audit(contracts, changed)
		except AssertionError: pass
		else: raise AssertionError(name)
	return list(mutations)


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('build', type=Path)
	parser.add_argument('runtime', type=Path)
	parser.add_argument('--receipt', type=Path, help='Existing ordinary full-registry capture receipt; no tests are launched')
	args = parser.parse_args(); build = args.build.resolve(strict=True); runtime = args.runtime.resolve()
	assert not build.is_relative_to(ROOT) and not runtime.is_relative_to(ROOT)
	configuration = json.loads((build / 'meson-info/meson-info.json').read_text())['directories']
	assert Path(configuration['source']).resolve() == ROOT and Path(configuration['build']).resolve() == build
	setup = build / 'meson-private/meson_test_setup.dat'; introspection = build / 'meson-info/intro-tests.json'
	setup_digest, intro_digest = sha(setup), sha(introspection)
	# These files belong to the already identity-checked live build above.
	with setup.open('rb') as stream: serialized = pickle.load(stream)
	intro = {row['name']: row for row in json.loads(introspection.read_text())}
	assert len(intro) == len(serialized) == len({row.name for row in serialized})
	contracts = {}
	for row in serialized:
		declaration = intro[row.name]
		assert row.timeout == declaration['timeout'] and row.is_parallel == declaration['is_parallel']
		assert row.protocol.name.lower() == declaration['protocol']
		# Empty input deliberately excludes every inherited host environment value.
		environment = row.env.get_env({}); assert environment == declaration['env']
		assert row.expected_exitcode is None or type(row.expected_exitcode) is int
		contracts[row.name] = dict(name=row.name, argv=declaration['cmd'], serialized_program=row.fname,
			serialized_arguments=row.cmd_args, expected_exit=0 if row.expected_exitcode is None else row.expected_exitcode,
			explicit_expected_exit=row.expected_exitcode, expected_fail=row.expected_fail, timeout=row.timeout,
			is_parallel=row.is_parallel, protocol=declaration['protocol'], workdir=row.workdir,
			declared_environment=environment, dependencies=row.depends)
	assert sha(setup) == setup_digest and sha(introspection) == intro_digest and contracts
	runtime.mkdir(parents=True, exist_ok=True); out = Path(tempfile.mkdtemp(prefix='registry-audit-', dir=runtime))
	receipt = dict(status='INVENTORY_AND_GUARD_CHECKS_PASS', scope='Contract inventory and audit counterexamples; registry execution not qualified',
		setup_sha256=setup_digest, introspection_sha256=intro_digest, recipe_sha256=sha(Path(__file__)),
		compiler_sha256=sha(build / 'astrac'), source_commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
		contracts=contracts, guard_refusals=guard_checks(), actual_registrations=len(contracts),
		serial_barriers=sum(not row['is_parallel'] for row in contracts.values()),
		explicit_exit_contracts=sum(row['explicit_expected_exit'] is not None for row in contracts.values()))
	def save(): (out / 'checks.json').write_text(json.dumps(receipt, indent=2) + '\n')
	save()
	if args.receipt:
		capture = json.loads(args.receipt.read_text()); raw = args.receipt.parent / 'registry.json'
		assert capture['registry_sha256'] == sha(introspection)
		assert capture['compiler_sha256'] == sha(build / 'astrac')
		assert capture['source_freeze']['commit'] == subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
		assert subprocess.run(['git', 'diff', '--quiet', 'HEAD'], cwd=ROOT).returncode == 0
		assert all(sha(ROOT / name) == digest for name, digest in capture['source_freeze']['tracked_files'].items())
		results = [{key: value for key, value in json.loads(line).items() if key != 'env'} for line in raw.read_text().splitlines()]
		assert results == capture['results']
		receipt.update(scope='Exact current full-registry source/command/exit/protocol/serial-interval audit',
			capture_sha256=sha(args.receipt), raw_results_sha256=sha(raw), status='REGISTRY_AUDIT_PENDING')
		save()
		try: audit(contracts, results)
		except BaseException:
			receipt['status'] = 'REGISTRY_NOT_QUALIFIED'; save(); raise
		receipt['status'] = 'PASS'; save()
	print(out / 'checks.json')


if __name__ == '__main__': main()
