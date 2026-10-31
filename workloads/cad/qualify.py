#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh local L/P reconstruction and required I-boundary probe; never skip inputs."""
import argparse
import collections
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

sys.dont_write_bytecode = True
from allocation_probe import probe
from compare import compare
from materialize import materialize
from prepare import BlockedInput, prepare


def checked(command, cwd, output, label, temporary, expected=0):
	env = dict(os.environ, CCACHE_DISABLE='1', CC='/usr/bin/gcc', PYTHONDONTWRITEBYTECODE='1', TMPDIR=str(temporary))
	start = time.monotonic()
	with (output / 'logs' / (label + '.log')).open('wb') as log:
		p = subprocess.run(list(map(str, command)), cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
	row = {'label': label, 'argv': list(map(str, command)), 'cwd': str(cwd), 'environment_overrides': {k: env[k] for k in ['CC', 'CCACHE_DISABLE', 'PYTHONDONTWRITEBYTECODE', 'TMPDIR']}, 'status': p.returncode, 'seconds_descriptive_only': time.monotonic() - start}
	with (output / 'commands.jsonl').open('a') as stream:
		stream.write(json.dumps(row) + '\n')
	if p.returncode != expected:
		raise RuntimeError(f'{label} exited {p.returncode}; inspect {output / "logs" / (label + ".log")}')
	print(label, 'complete', flush=True)


def suite(build, expected):
	rows = [json.loads(line) for line in (build / 'meson-logs/testlog.json').read_text().splitlines()]
	registered = json.loads((build / 'meson-info/intro-tests.json').read_text())
	counts = dict(collections.Counter(row['result'] for row in rows))
	if len(rows) != len(registered) or len(rows) != expected or counts != {'OK': expected}:
		raise RuntimeError(f'incomplete/failed suite {build}: {len(rows)}, {len(registered)}, {counts}')
	return {'tests': len(rows), 'results': counts, 'testlog_sha256': hashlib.sha256((build / 'meson-logs/testlog.json').read_bytes()).hexdigest()}


def controls(build, historical):
	results = {}
	for name, directory in [('synthetic', 'Synthetic'), ('differential', 'Differential')]:
		for row in json.loads((build / 'test-results' / directory / 'results.json').read_text()):
			results[name, row['name']] = {'iterations': row['iterations'], 'output_sha256': hashlib.sha256((build / 'test-results' / directory / (row['name'] + '-output.png')).read_bytes()).hexdigest()}
	for case in ['natural', 'cartoon', 'pixel-art', 'near-cardinal']:
		row = json.loads((build / 'test-results/References' / (case + '.json')).read_text())
		results['references', case] = {key: row[key] for key in ['iterations', 'output_sha256']}
	rows = []
	for control in historical['cad1_comparison']:
		name = control['suite']
		case = control['case']
		candidates = historical['references'] if name == 'references' else historical[name]['cases']
		expected = next(row for row in candidates if row.get('case', row.get('name')) == case)
		actual = results[name, case]
		row = {'suite': name, 'case': case, 'iterations': actual['iterations'], 'output_sha256': actual['output_sha256'], 'equal': all(actual[key] == expected[key] for key in actual)}
		rows.append(row)
	if len(rows) != 37 or not all(row['equal'] for row in rows):
		raise RuntimeError(f'historical hash/iteration mismatch: {[row for row in rows if not row["equal"]]}')
	return rows


def qualify(args):
	out = args.output.resolve()
	# prepare() fails closed before any compiler/application build. All source
	# authorities, original oracle, dependencies and local images are mandatory.
	if prepare(argparse.Namespace(compiler_repository=args.compiler_repository, cad_repository=args.cad_repository, assets=args.assets, output=out, extract=True)):
		return 2
	(out / 'logs').mkdir()
	(out / 'tmp').mkdir()
	result = {'status': 'INCOMPLETE', 'routes': {}}
	try:
		historical = json.loads((out / 'references/ASTRA-CAD-2-VALIDATION.json').read_text())
		for route, source_name, count in [('L', 'historical-compiler', 6726), ('P', 'current', 9067)]:
			temporary = out / 'tmp' / route
			temporary.mkdir()
			compiler_build = out / (route + '-compiler')
			checked(['meson', 'setup', compiler_build, out / 'sources' / source_name, '-Dwerror=true', '-Ddebug=false', '--prefix=' + str(out / (route + '-prefix')), '--datadir=share', '--libdir=lib64'], out, out, route + '-compiler-setup', temporary)
			checked(['meson', 'compile', '-C', compiler_build, '-j' + str(args.jobs)], out, out, route + '-compiler-build', temporary)
			checked(['meson', 'test', '-C', compiler_build, '--no-rebuild', '--print-errorlogs', '-j' + str(args.jobs)], out, out, route + '-compiler-tests', temporary)
			result['routes'][route] = {'compiler': suite(compiler_build, count)}
			application = out / 'sources/cad'
			options = []
			if route == 'P':
				application = out / 'sources/P'
				manifest = materialize(out / 'sources/cad', out / 'cad-members.json', application)
				(out / 'P-source.json').write_text(json.dumps(manifest, indent='\t') + '\n')
				options = ['-Dargs_provider=' + str(compiler_build / 'lib/astra/args-posix.o')]
			build = out / (route + '-cad')
			checked(['meson', 'setup', build, application, '-Dwerror=true', '-Ddebug=false', '-Dastra_compiler=' + str(compiler_build / 'astrac'), '-Dreference_data=' + str(out / 'assets'), *options], out, out, route + '-cad-setup', temporary)
			checked(['meson', 'compile', '-C', build, '-j' + str(args.jobs)], out, out, route + '-cad-build', temporary)
			checked(['meson', 'test', '-C', build, '--no-rebuild', '--print-errorlogs', '-j' + str(min(args.jobs, 4))], out, out, route + '-cad-tests', temporary)
			result['routes'][route]['application'] = suite(build, 13)
			result['routes'][route]['historical_controls'] = controls(build, historical)
		parity = compare(out / 'L-cad/test-results', out / 'P-cad/test-results')
		(out / 'native-parity.json').write_text(json.dumps(parity, indent='\t') + '\n')
		if parity['status'] != 'EXACT_RETAINED_ARTIFACTS':
			raise RuntimeError('native L/P mismatch; inspect native-parity.json')
		result['native_artifacts_compared'] = len(parity['rows'])
		result['I'] = probe(out / 'P-compiler/astrac', out / 'P-compiler/lib/astra/args-posix.o', out / 'I-allocation-boundary')
		result['status'] = result['I']['status']
		result['scope'] = 'L/P correctness plus required I allocation boundary; full I, I timing and I installed qualification are not completed.'
	except (OSError, RuntimeError, ValueError) as error:
		result['status'] = 'INCOMPLETE'
		result['failure'] = str(error)
	finally:
		(out / 'qualification.json').write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps({'status': result['status'], 'record': str(out / 'qualification.json')}, indent='\t'))
	return 3 if result['status'] == 'BLOCKED_COMPILER' else 1


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler-repository', type=Path, default=Path(__file__).resolve().parents[2])
	parser.add_argument('--cad-repository', type=Path, required=True)
	parser.add_argument('--assets', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--jobs', type=int, choices=range(1, 9), default=8)
	try:
		return qualify(parser.parse_args())
	except BlockedInput as error:
		print(json.dumps({'status': 'BLOCKED_INPUT', 'missing': [str(error)]}, indent='\t'))
		return 2


if __name__ == '__main__':
	sys.exit(main())
