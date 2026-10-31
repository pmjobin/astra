#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Discover the complete Meson registry and bind all 132 application identities.

An optional ordinary Meson invocation records a fresh frozen-source run. This
does not qualify external Windows/editor/installed-release gates by inference.
"""
from pathlib import Path
import argparse
import collections
import hashlib
import json
import os
import re
import subprocess
import tempfile
import time
import sys

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	with Path(path).open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def git(*args):
	return subprocess.check_output(['git', *args], cwd=ROOT)


def applications(names):
	rows = []
	def add(number, sources, tests, auxiliary=()):
		assert all((ROOT / source).is_file() for source in sources), (number, sources)
		assert set(tests) <= names, (number, set(tests) - names)
		rows.append({'id': f'A{number:02d}', 'sources': {source: sha(ROOT / source) for source in sources},
			'registrations': tests, 'additional_required_qualification': list(auxiliary)})
	def group(start, directory, stems, test):
		for number, stem in enumerate(stems.split(), start):
			add(number, [f'examples/{directory}/{stem}.astra'], [test])
	group(1, 'application-runtime', 'format-matrix text-ops copy-bytes io-errors diagnostic-transform kv-config line-stat owner-log', 'application-runtime-1-execution')
	group(9, 'compiler-systems', 'optimized-diagnostics bulk-copy wide-counter namespace-same-name module-config file-digest64 object-link-client systems-report', 'compiler-systems-2-applications')
	group(17, 'language-runtime-3', 'interface-dispatch polymorphic-diagnostics callable-stream-transform closure-ledger c-record-bridge c-callback-provider property-replacement composed-event-report', 'language-runtime-3-applications')
	group(25, 'language-runtime-4', 'shared-document weak-subscribers shared-diagnostics', 'shared-1b-applications')
	for number, stem, test in [(28, 'function-pipeline', 'callable'), (29, 'owning-message-transform', 'closure'),
		(30, 'checked-closure-rollback', 'closure'), (31, 'sync-event-bridge', 'events'), (32, 'observer-report', 'report')]:
		add(number, [f'examples/language-runtime-4/{stem}.astra'], ['language-runtime-4-' + test])
	for number, stem, test in [(33, 'deferred-event-subscriber', 'retained'), (34, 'weak-document-observer', 'retained'),
		(35, 'checked-event-transformer', 'retained'), (36, 'record-diagnostics', 'record'), (37, 'binary-ingest', 'payload'),
		(38, 'segmented-copy', 'payload'), (39, 'cancellable-scan', 'payload'), (40, 'event-diagnostic-importer', 'importer')]:
		add(number, [f'examples/interop-async-5/{stem}.astra'], ['interop-async-5-' + test])
	group(41, 'owned-state-6', 'lazy-diagnostic-card retryable-settings-reader nested-resource-event record-batch-rollback bounded-spool-allocator scoped-buffer-index diagnostic-queue-editor cached-diagnostic-rewriter', 'owned-state-6-runtime')
	group(49, 'language-usability-7', 'counted-record-scanner diagnostic-bag-report nullable-boundary-processor ordered-policy-engine scoped-config-renderer float-telemetry-report source-inspector diagnostic-transform-pipeline', 'language-usability-7-applications')
	for number in range(57, 130):
		if number <= 64:
			directory, tests = 'ecosystem-abi-8', ['ecosystem-abi-8-applications']
		elif number <= 72:
			directory = 'systems-dsp-9'
			tests = ['systems-dsp-9-' + {65: 'minimal', 66: 'numeric', 67: 'numeric', 68: 'arena', 69: 'volatile', 70: 'arena', 71: 'portability', 72: 'portability'}[number]]
		elif number <= 84:
			directory, tests = 'language-generalization-10', [f'language-generalization-10-application-a{number}']
		elif number <= 96:
			directory = 'numerical-optimization-11'
			tests = ['numerical-optimization-11-policies' if number == 92 else f'numerical-optimization-11-application-a{number}']
		elif number <= 108:
			directory = 'freestanding-allocation-12'
			tests = ['freestanding-allocation-12-' + {97: 'guest', 98: 'policies', 99: 'devices', 100: 'devices', 101: 'owners', 102: 'owners', 103: 'owners', 104: 'owners', 105: 'owners', 106: 'owners', 107: 'owners', 108: 'policies'}[number]]
			if number == 101:
				tests.append('freestanding-allocation-12-policies')
		elif number <= 120:
			directory, tests = 'concurrency-runtime-13', ['concurrency-runtime-13-applications']
		else:
			directory = 'interop-tooling-14'
			tests = [f'interop-tooling-14-a{number}'] if number in (121, 122) else ['interop-tooling-14-gobject-applications'] if number in (126, 127, 128) else []
		if number == 129:
			add(number, ['examples/interop-tooling-14/a129/main.astra', 'examples/interop-tooling-14/a129/records.astra', 'examples/interop-tooling-14/a129/transformer.astra'], ['interop-tooling-14-a129'], ['a129-packaged-transformer.py --prefix FINAL_RELEASE_PREFIX'])
			continue
		sources = sorted(str(p.relative_to(ROOT)) for p in (ROOT / 'examples' / directory).rglob(f'a{number}-*.astra'))
		assert sources, number
		additional = ['windows-applications.py build + native Windows capture.py --profile applications'] if number in (123, 124, 125) else []
		add(number, sources, tests, additional)
	add(130, [f'examples/interop-tooling-14/editor-project/{stem}.astra' for stem in ('main', 'library', 'other')], ['interop-tooling-14-lsp'], ['actual VS Code editor client'])
	add(131, ['examples/interop-tooling-14/a131/main.astra', 'examples/interop-tooling-14/a131/math.astra'], ['interop-tooling-14-a131'])
	add(132, ['examples/interop-tooling-14/a132/main.astra'], ['interop-tooling-14-a132-development'], ['a132-installed-system.py --prefix FINAL_RELEASE_PREFIX'])
	assert len(rows) == len({row['id'] for row in rows}) == 132
	return rows


def snapshot():
	assert subprocess.run(['git', 'diff', '--quiet', 'HEAD'], cwd=ROOT).returncode == 0, 'commit tracked task inputs before a frozen-source run'
	return {'commit': git('rev-parse', 'HEAD').decode().strip(),
		'tracked_files': {os.fsdecode(name): sha(ROOT / os.fsdecode(name)) for name in git('ls-files', '-z').split(b'\0') if name and (ROOT / os.fsdecode(name)).is_file()}}


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--build', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--run', action='store_true')
	parser.add_argument('--jobs', type=int, default=4)
	parser.add_argument('--auxiliary', action='store_true', help='run the portable safety/cost catalog after a fully passing registry')
	parser.add_argument('--installed-prefix', type=Path)
	parser.add_argument('--liburing-prefix', type=Path)
	args = parser.parse_args()
	assert 1 <= args.jobs <= 8
	if args.auxiliary:
		assert args.run and args.installed_prefix and args.liburing_prefix
	build, output = args.build.resolve(), args.output.resolve()
	assert not output.is_relative_to(ROOT) and not build.is_relative_to(ROOT)
	directories = json.loads((build / 'meson-info/meson-info.json').read_text())['directories']
	assert Path(directories['source']).resolve() == ROOT and Path(directories['build']).resolve() == build
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='surge14-registry-', dir=output))
	tests_path = build / 'meson-info/intro-tests.json'
	tests = json.loads(tests_path.read_text())
	names = {test['name'] for test in tests}
	assert len(names) == len(tests), 'duplicate registration names require explicit reconciliation'
	receipt = {'format': 'astra-surge14-qualification/1', 'stage': 'INVENTORY_ONLY',
		'build': str(build), 'registry_sha256': sha(tests_path), 'registry': tests,
		'applications': applications(names), 'source_commit': git('rev-parse', 'HEAD').decode().strip(),
		'build_options': json.loads((build / 'meson-info/intro-buildoptions.json').read_text())}
	catalog_path = ROOT / 'tools/qualification/surge14-auxiliary.json'
	catalog = json.loads(catalog_path.read_text())
	assert catalog['format'] == 'astra-surge14-auxiliary/1'
	assert len({row['id'] for row in catalog['recipes']}) == len(catalog['recipes'])
	receipt['auxiliary_catalog'] = {'sha256': sha(catalog_path), 'recipes': catalog['recipes'],
		'script_hashes': {row['script']: sha(ROOT / row['script']) for row in catalog['recipes']}}
	# These portable manifests are selections of registered tests, not extra
	# executions. Older shell wrappers also reconfigure an older build profile;
	# the complete present registry supplies their named test coverage directly.
	receipt['portable_selection_manifests'] = []
	for relative in git('ls-files', '-z').split(b'\0'):
		if not relative:
			continue
		path = ROOT / os.fsdecode(relative)
		if path.name not in ('integration-tests.json', 'features.json') or not path.is_relative_to(ROOT / 'tests'):
			continue
		data = json.loads(path.read_text())
		selected = data if isinstance(data, list) else [name for cases in data['features'].values() for name in cases]
		assert all(isinstance(name, str) and (name in names or name.endswith('.sh') and (ROOT / name).is_file()) for name in selected), path
		receipt['portable_selection_manifests'].append({'path': str(path.relative_to(ROOT)), 'sha256': sha(path),
			'registrations': [name for name in selected if name in names],
			'retained_selection_wrappers': [name for name in selected if name not in names]})
	def save():
		(work / 'qualification.json').write_text(json.dumps(receipt, indent=2) + '\n')
	save()
	print(f'Inventory: {len(tests)} registrations, {len(receipt["applications"])} distinct source-backed applications; {work}', flush=True)
	if not args.run:
		return
	receipt['source_freeze'] = snapshot()
	compiler = build / 'astrac'
	receipt['compiler_sha256'] = sha(compiler)
	command = ['meson', 'test', '-C', str(build), '--no-rebuild', '--num-processes', str(args.jobs),
		'--print-errorlogs', '--logbase', str(work / 'registry')]
	receipt['command'] = command
	receipt['started_unix'] = time.time()
	receipt['stage'] = 'RUNNING'
	save()
	with (work / 'console.log').open('w') as stream:
		result = subprocess.run(command, cwd=ROOT, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'), stdout=stream, stderr=subprocess.STDOUT)
	receipt['exit'] = result.returncode
	receipt['elapsed_seconds'] = time.time() - receipt['started_unix']
	receipt['source_unchanged'] = snapshot() == receipt['source_freeze']
	receipt['compiler_unchanged'] = sha(compiler) == receipt['compiler_sha256']
	receipt['registry_unchanged'] = sha(tests_path) == receipt['registry_sha256']
	log = work / 'registry.json'
	# The raw Meson log remains external. Do not copy inherited process
	# environments into the compact engineering evidence index.
	receipt['results'] = [{key: value for key, value in json.loads(line).items() if key != 'env'}
		for line in log.read_text().splitlines()] if log.is_file() else []
	observed = [row['name'].removeprefix('astra:') for row in receipt['results']]
	receipt['missing'] = sorted(names - set(observed))
	receipt['unexpected'] = sorted(set(observed) - names)
	receipt['duplicates'] = [name for name, count in collections.Counter(observed).items() if count != 1]
	receipt['nonpassing'] = [row for row in receipt['results'] if row['result'] != 'OK']
	receipt['tap_skips'] = [{'registration': row['name'], 'line': line} for row in receipt['results']
		for line in row.get('stdout', '').splitlines() if re.match(r'^\s*(?:not )?ok\s+\d+.*#\s*SKIP\b', line, re.I)]
	valid = result.returncode == 0 and receipt['source_unchanged'] and receipt['compiler_unchanged'] and receipt['registry_unchanged'] and not any(receipt[key] for key in ('missing', 'unexpected', 'duplicates', 'nonpassing', 'tap_skips'))
	receipt['stage'] = 'REGISTRY_PASS_AUXILIARY_AND_EXTERNAL_GATES_PENDING' if valid else 'REGISTRY_NOT_QUALIFIED'
	save()
	if valid and args.auxiliary:
		aux_output = build / 'interop-tooling-14/qualification-auxiliary' / work.name
		values = {'compiler': str(compiler), 'build': str(build), 'output': str(aux_output),
			'installed_compiler': str(args.installed_prefix.resolve() / 'bin/astrac'),
			'liburing_prefix': str(args.liburing_prefix.resolve())}
		assert Path(values['installed_compiler']).is_file()
		receipt['installed_compiler_sha256'] = sha(values['installed_compiler'])
		receipt['auxiliary_results'] = []
		for item in catalog['recipes']:
			command = [sys.executable, '-B', str(ROOT / item['script']), *[value.format(**values) for value in item['arguments']]]
			console = work / (item['id'] + '.log')
			started = time.time()
			with console.open('w') as stream:
				p = subprocess.run(command, cwd=ROOT, env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'), stdout=stream, stderr=subprocess.STDOUT, timeout=3600)
			path = Path(item['receipt'].format(**values))
			data = json.loads(path.read_text()) if path.is_file() else {}
			commands = data.get('commands', [])
			good = p.returncode == 0 and data.get('status') == 'PASS' and bool(commands)
			if item['id'] == 'independent-installed-liburing-timer':
				good &= data.get('compiler_sha256') == receipt['installed_compiler_sha256'] and all(row['passed'] for row in commands)
			else:
				good &= data.get('compiler', {}).get('sha256') == receipt['compiler_sha256'] and all(row['exit'] == row['expected_exit'] for row in commands)
			receipt['auxiliary_results'].append({'id': item['id'], 'command': command, 'exit': p.returncode,
				'seconds': time.time() - started, 'receipt': str(path), 'receipt_sha256': sha(path) if path.is_file() else None,
				'command_count': len(commands), 'passed': bool(good), 'console_sha256': sha(console)})
			save()
			print(f'Auxiliary {item["id"]}: {"PASS" if good else "FAILED"}', flush=True)
			if not good:
				valid = False
				break
		receipt['source_unchanged_after_auxiliary'] = snapshot() == receipt['source_freeze']
		receipt['compiler_unchanged_after_auxiliary'] = sha(compiler) == receipt['compiler_sha256']
		receipt['installed_compiler_unchanged'] = sha(values['installed_compiler']) == receipt['installed_compiler_sha256']
		valid &= receipt['source_unchanged_after_auxiliary'] and receipt['compiler_unchanged_after_auxiliary'] and receipt['installed_compiler_unchanged']
		receipt['stage'] = 'REGISTRY_AND_AUXILIARY_PASS_EXTERNAL_GATES_PENDING' if valid else 'AUXILIARY_NOT_QUALIFIED'
		save()
	print(f'{receipt["stage"]}: {len(receipt["results"])} results; evidence {work}', flush=True)
	raise SystemExit(0 if valid else 1)


if __name__ == '__main__':
	main()
