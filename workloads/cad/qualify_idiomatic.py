#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""APP-CAD-2: verify the original inputs and materialize a versioned resumption."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys

sys.dont_write_bytecode = True
from prepare import BlockedInput, check_assets, check_dependencies, extract_exact, git, sha256, verify_repository
from qualify import controls, suite

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BASELINE = {'revision': '0e847be42a00be7f8d85c4c50f813a8d0c540cb3', 'tree': 'dd64e3df06dbb29331c6f1b042952b2f0a0aac7c'}


def write(path, value):
	path.write_text(json.dumps(value, indent='\t') + '\n')


def members(directory):
	return {str(p.relative_to(directory)): {'sha256': sha256(p), 'mode': format(stat.S_IMODE(p.stat().st_mode), '06o'), 'bytes': p.stat().st_size} for p in sorted(directory.rglob('*')) if p.is_file()}


def compatibility(reference, output):
	"""Apply the unchanged APP-CAD-1 recipe without writing its historical root."""
	shutil.copytree(reference, output)
	command = ['git', 'apply', '--directory=' + str(output.relative_to(ROOT)), str(HERE / 'compat/port.patch')]
	subprocess.run(command, cwd=ROOT, env=dict(os.environ, GIT_OPTIONAL_LOCKS='0'), check=True, capture_output=True)
	for origin, target in [('arguments.c', 'native/arguments.c'), ('entry.astra', 'src/entry.astra')]:
		shutil.copyfile(HERE / 'compat' / origin, output / target)
	return {'route': 'P', 'patch_sha256': sha256(HERE / 'compat/port.patch'), 'members': members(output)}


def idiomatic(reference, output):
	compatibility(reference, output)
	recipe = json.loads((HERE / 'idiomatic/origins.json').read_text())
	command = ['git', 'apply', '--directory=' + str(output.relative_to(ROOT)), str(HERE / 'idiomatic/port.patch')]
	subprocess.run(command, cwd=ROOT, env=dict(os.environ, GIT_OPTIONAL_LOCKS='0'), check=True, capture_output=True)
	for name in recipe['replacements']:
		shutil.copyfile(HERE / 'idiomatic' / name, output / name)
	for name, row in recipe['changed_members'].items():
		if sha256(output / name) != row['I_sha256'] or format(stat.S_IMODE((output / name).stat().st_mode), '06o') != row['mode']:
			raise ValueError('idiomatic recipe member differs: ' + name)
	return {'route': 'I', 'recipe_sha256': sha256(HERE / 'idiomatic/origins.json'), 'members': members(output)}


def execute(command, out, label, cwd=ROOT):
	env = dict(os.environ, CC='/usr/bin/gcc', CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', TMPDIR=str(out / 'tmp'))
	command = list(map(str, command))
	with (out / 'logs' / (label + '.log')).open('wb') as log:
		process = subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT)
	with (out / 'commands.jsonl').open('a') as stream:
		stream.write(json.dumps({'argv': command, 'cwd': str(cwd), 'status': process.returncode, 'environment': {key: env[key] for key in ['CC', 'CCACHE_DISABLE', 'PYTHONDONTWRITEBYTECODE', 'TMPDIR']}}) + '\n')
	if process.returncode:
		raise RuntimeError(label + ' failed; inspect ' + str(out / 'logs' / (label + '.log')))
	print(label + ' complete', flush=True)


def preflight(args, out):
	pins = json.loads((HERE / 'pins.json').read_text())
	record = {'status': 'BLOCKED_INPUT', 'APP_CAD_FULL_I': 'NOT_RUN/INCOMPLETE', 'missing': []}
	try:
		if args.acceptance:
			for name, path in [('compiler', args.compiler), ('ARGS provider', args.args_provider)]:
				if not path.is_file() or not os.access(path, os.R_OK) or (name == 'compiler' and not os.access(path, os.X_OK)):
					raise BlockedInput('unavailable ' + name + ': ' + str(path))
			record['execution_inputs'] = {'compiler_sha256': sha256(args.compiler), 'args_provider_sha256': sha256(args.args_provider)}
		record['compiler'] = verify_repository(ROOT, BASELINE)
		record['cad'] = verify_repository(args.cad_repository, pins['cad'])
		record['historical_compiler'] = verify_repository(ROOT, pins['historical-compiler'])
		record['historical_report'] = verify_repository(args.cad_repository, pins['historical-report'])
		record['assets'] = check_assets(args.assets, pins['assets'])
		record['dependencies'] = check_dependencies()
		for name, item in pins['historical-report']['files'].items():
			data = git(args.cad_repository, 'show', pins['historical-report']['revision'] + ':' + name)
			blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
			if hashlib.sha256(data).hexdigest() != item['sha256'] or blob != item['git_blob']:
				raise BlockedInput('historical report differs: ' + name)
			(out / 'references' / Path(name).name).write_bytes(data)
		record['source'] = extract_exact(args.cad_repository, pins['cad'], out / 'original', out / 'original.tar')
		if record['source']['members'] != json.loads((HERE / 'cad-members.json').read_text()):
			raise BlockedInput('original source differs from committed CAD member inventory')
		record['P'] = compatibility(out / 'original', out / 'P-source')
		record['status'] = 'INPUTS_VERIFIED'
	except (BlockedInput, OSError) as error:
		record['missing'].append(str(error))
	finally:
		write(out / 'preflight.json', record)
	return record


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--cad-repository', type=Path, required=True)
	parser.add_argument('--assets', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	mode = parser.add_mutually_exclusive_group(required=True)
	mode.add_argument('--preflight', action='store_true')
	mode.add_argument('--acceptance', action='store_true', help='build I and execute all thirteen original acceptance entries; campaign ownership/install obligations remain separate')
	parser.add_argument('--compiler', type=Path)
	parser.add_argument('--args-provider', type=Path)
	args = parser.parse_args()
	if args.acceptance and (args.compiler is None or args.args_provider is None):
		parser.error('--acceptance requires --compiler and --args-provider')
	out = args.output.resolve()
	if not out.is_relative_to(ROOT / 'build/app-cad-2') or out == ROOT / 'build/app-cad-2':
		parser.error('output must be a fresh child of build/app-cad-2/')
	out.mkdir(parents=True, exist_ok=False)
	(out / 'references').mkdir()
	record = preflight(args, out)
	if args.acceptance and not record['missing']:
		(out / 'logs').mkdir()
		(out / 'tmp').mkdir()
		result = {'status': 'INCOMPLETE', 'APP_CAD_FULL_I': 'NOT_RUN/INCOMPLETE'}
		try:
			result['source'] = idiomatic(out / 'original', out / 'I-source')
			build = out / 'I-build'
			execute(['meson', 'setup', build, out / 'I-source', '-Dwerror=true', '-Ddebug=false', '-Dastra_compiler=' + str(args.compiler.resolve()), '-Dargs_provider=' + str(args.args_provider.resolve()), '-Dreference_data=' + str(args.assets.resolve())], out, 'setup')
			execute(['meson', 'compile', '-C', build, '-j2'], out, 'build')
			execute(['meson', 'test', '-C', build, '--no-rebuild', '--print-errorlogs', '-j2', '--timeout-multiplier=2'], out, 'acceptance')
			result['suite'] = suite(build, 13)
			result['controls'] = controls(build, json.loads((out / 'references/ASTRA-CAD-2-VALIDATION.json').read_text()))
			result['programs_and_adapters'] = {name: sha256(build / name) for name in ['astra-cad', 'numeric-tests', 'algorithm-tests', 'step-tests', 'orientation-tests', 'libcad-io.so', 'libcad-test-io.so']}
			result['compiler_sha256'] = sha256(args.compiler.resolve())
			result['args_provider_sha256'] = sha256(args.args_provider.resolve())
			result['status'] = 'I_ORIGINAL_ACCEPTANCE_PASS'
			result['scope'] = 'One complete original 13-entry/37-control I run. Exact native parity, memory, installation and final compiler suites are separate obligations; this receipt alone is not full I PASS.'
		finally:
			write(out / 'result.json', result)
	print(json.dumps({'status': result['status'] if args.acceptance and not record['missing'] else record['status'], 'APP_CAD_FULL_I': record['APP_CAD_FULL_I'], 'missing': record['missing']}))
	return 2 if record['missing'] else 0


if __name__ == '__main__':
	sys.exit(main())
