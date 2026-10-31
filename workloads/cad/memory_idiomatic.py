#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""APP-CAD-2 normal memory, exact allocation-site failures and ownership traces."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
from observe_idiomatic import prepare
from compare import compare

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
	with path.open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def qualify(args):
	out = args.output.resolve()
	out.mkdir(parents=True, exist_ok=False)
	(out / 'tmp').mkdir()
	program = args.build.resolve() / 'astra-cad'
	constant = args.inputs.resolve() / 'constant-37-119-213-input.png'
	line = args.inputs.resolve() / 'narrow-line-input.png'
	for path in [program, constant, line, args.maximum_input]:
		assert path.is_file(), path
	observer = out / 'observer'
	sites = prepare(args.compiler.resolve(), args.source.resolve(), program, observer)
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', TMPDIR=str(out / 'tmp'), LD_LIBRARY_PATH=str(program.parent))
	rows = []
	def run(name, arguments, expected, memory=False, observed=False, failure=None, limit=False, binary=program, fatal=False):
		folder = out / name
		folder.mkdir()
		arguments = [folder / 'output.png' if str(value) == str(out / 'trace-output.png') else folder / 'trace' if str(value) == str(out / 'trace') else value for value in arguments]
		command = [str(binary), *map(str, arguments)]
		selected = env.copy()
		if observed:
			selected.update(LD_PRELOAD=str(observer / 'observer.so'), CAD_OBSERVER_OUTPUT=str(folder / 'observer.json'), CAD_EVENTS=str(folder / 'events.jsonl'))
		if failure is not None:
			selected['CAD_FAIL_SITE'] = str(failure)
		if memory:
			command = ['valgrind', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', '--error-exitcode=97', '--xml=yes', '--xml-file=' + str(folder / 'valgrind.xml'), *command]
		def limits():
			resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
			if limit:
				resource.setrlimit(resource.RLIMIT_AS, (64 * 1024 * 1024, 64 * 1024 * 1024))
		process = subprocess.run(command, cwd=folder, env=selected, capture_output=True, preexec_fn=limits)
		(folder / 'stdout').write_bytes(process.stdout)
		(folder / 'stderr').write_bytes(process.stderr)
		row = {'name': name, 'argv': command, 'cwd': str(folder), 'binary_sha256': digest(binary), 'expected': expected, 'status': process.returncode, 'memory': memory, 'observer': observed, 'fatal': fatal or failure is not None or limit, 'limit_bytes': 64 * 1024 * 1024 if limit else None}
		if memory:
			xml = ET.parse(folder / 'valgrind.xml')
			row['memory_errors'] = [{'kind': e.findtext('kind'), 'text': e.findtext('xwhat/text'), 'bytes': int(e.findtext('xwhat/leakedbytes') or 0)} for e in xml.findall('error') if e.findtext('kind') != 'Leak_StillReachable']
			row['finished'] = xml.findall('status')[-1].findtext('state') == 'FINISHED'
		if observed:
			row['observation'] = json.loads((folder / 'observer.json').read_text())
			row['events'] = [json.loads(text) for text in (folder / 'events.jsonl').read_text().splitlines()] if (folder / 'events.jsonl').exists() else []
		rows.append(row)
		(out / 'records.json').write_text(json.dumps(rows, indent='\t') + '\n')
		assert process.returncode == expected, row
		if memory:
			assert row['finished'] and not row['memory_errors'], row
		if observed:
			observation = row['observation']
			assert observation['errors'] == 0, row
			if not row['fatal']:
				assert observation['allocations'] == observation['releases'] and observation['live_bytes'] == observation['live_count'] == 0, row
				assert observation['last_numeric_release'] < observation['argument_release'] < observation['ARGS_snapshot_release'], row
		return row, process
		# Every run has a distinct output; stale images cannot establish success.
	cases = [(f'constant-{i}', constant, 4, 3, [], 0) for i in range(3)]
	cases += [('narrow-line', line, 8, 8, ['--pixel-art'], 0), ('ceiling', line, 8, 8, ['--pixel-art', '--max-iterations', '1'], 3), ('write-error', constant, 4, 3, [], 1)]
	for name, source, width, height, options, status in cases:
		for mode in ['normal', 'observed']:
			output = out / (name + '-' + mode + '.png') if name != 'write-error' else out / 'absent' / 'output.png'
			row, process = run(name + '-' + mode, [source, output, width, height, *options], status, memory=mode == 'normal', observed=mode == 'observed')
			if status != 1:
				assert output.is_file()
				row['png_sha256'] = digest(output)
			if mode == 'normal':
				before, before_row = process, row
			else:
				assert process.stdout == before.stdout and process.stderr == before.stderr
				assert row.get('png_sha256') == before_row.get('png_sha256')
	for name, arguments in [('usage', []), ('missing-input', [out / 'missing.png', out / 'unused.png', 1, 1])]:
		run(name, arguments, 1, memory=True)
		# Reach all eleven correction scratch requests with the original narrow line.
	trace_arguments = [line, out / 'trace-output.png', 8, 8, '--pixel-art', '--max-iterations', 3, '--dump-state', out / 'trace', '--observe-corrections']
	trace, _ = run('trace-success', trace_arguments, 3, observed=True)
	run('trace-plain', trace_arguments, 3)
	parity = compare(out / 'trace-success', out / 'trace-plain')
	(out / 'trace-parity.json').write_text(json.dumps(parity, indent='\t') + '\n')
	assert parity['status'] == 'EXACT_RETAINED_ARTIFACTS', parity['first_difference_in_sorted_artifact_order']
	reached = {row['site'] for row in trace['events'] if row['event'] == 'allocate'}
	assert reached == {row['id'] for row in sites['sites'] if not row['empty']}, reached
	for site in sites['sites']:
		if site['empty']:
			continue
		row, process = run('failure-' + str(site['id']) + '-' + site['name'], trace_arguments, 2, observed=True, failure=site['id'])
		failure = [event for event in row['events'] if event['event'] == 'failure']
		assert len(failure) == 1 and failure[0]['site'] == site['id'], row
		count = failure[0]['count'] * site['historical_slots_per_element']
		assert process.stdout == b'' and process.stderr == f'astra-cad: failure 3 (value {count})\n'.encode(), row
		row['historical_diagnostic_slots'] = count
		# The real maximum-image test retains the original 64 MiB address-space limit.
	row, process = run('maximum-image', [args.maximum_input.resolve(), out / 'maximum.png', 2048, 2048], 2, observed=True, limit=True)
	assert process.stdout == b'' and process.stderr == b'astra-cad: failure 3 (value 37748736)\n'
	assert row['events'][-1] == {'event': 'allocator-null', 'site': 1, 'count': 4194304, 'stride': 72, 'sequence': 1}, row
	# Valgrind replaces calloc itself, bypassing LD_PRELOAD allocation injection.
	# Keep injection outside it; measure a real original fatal output path here.
	# mkdir accepts EEXIST for this file; opening its child fails and exits(2).
	blocked_directory = out / 'dump-is-file'
	blocked_directory.write_text('original fatal dump-path control\n')
	run('fatal-output-memory', [constant, out / 'fatal.png', 4, 3, '--dump-state', blocked_directory], 2, memory=True, fatal=True)
	(out / 'records.json').write_text(json.dumps(rows, indent='\t') + '\n')
	print(json.dumps({'normal_valgrind': sum(row['memory'] and not row['fatal'] for row in rows), 'fatal_valgrind': sum(row['memory'] and row['fatal'] for row in rows), 'injected_sites': sum(not row['empty'] for row in sites['sites']), 'records': len(rows)}))


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler', 'source', 'build', 'inputs', 'maximum-input', 'output']:
		parser.add_argument('--' + name, type=Path, required=True)
	qualify(parser.parse_args())
