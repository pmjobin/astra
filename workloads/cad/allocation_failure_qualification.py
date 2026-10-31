#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Candidate P regression and explicit fatal-boundary supplement; never full I."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
from compare import compare
from prepare import check_assets, extract_exact, verify_repository
from qualify import controls, suite

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def digest(path):
	with path.open('rb') as stream:
		return hashlib.file_digest(stream, 'sha256').hexdigest()


def qualify(args):
	out = args.output.resolve()
	if not out.is_relative_to(ROOT / 'build/alloc-fail-1'):
		raise ValueError('new evidence must be under build/alloc-fail-1/')
	out.mkdir(parents=True, exist_ok=False)
	(out / 'logs').mkdir()
	(out / 'tmp').mkdir()
	env = dict(os.environ, CCACHE_DISABLE='1', CC='/usr/bin/gcc', TMPDIR=str(out / 'tmp'), PYTHONDONTWRITEBYTECODE='1')
	commands = []
	def run(argv, label, cwd=ROOT):
		with (out / 'logs' / (label + '.log')).open('wb') as stream:
			p = subprocess.run(list(map(str, argv)), cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT)
		commands.append(dict(label=label, argv=list(map(str, argv)), cwd=str(cwd), status=p.returncode))
		(out / 'commands.json').write_text(json.dumps(commands, indent='\t') + '\n')
		assert p.returncode == 0, commands[-1]
		print(label, 'complete', flush=True)
	result = dict(status='INCOMPLETE', APP_CAD_FULL_I='NOT_RUN/INCOMPLETE', historical_APP_CAD_1='BLOCKED_COMPILER')
	try:
		pins = json.loads((HERE / 'pins.json').read_text())
		retained = args.retained_root.resolve()
		accepted = json.loads((ROOT / 'docs/app-cad-1-evidence.json').read_text())
		result['pins'] = dict(cad=verify_repository(args.cad_repository, pins['cad']), historical_compiler=verify_repository(ROOT, pins['historical-compiler']))
		result['assets'] = check_assets(retained / 'assets', pins['assets'])
		for name, directory in [('L-compiler', 'L-compiler'), ('L-cad', 'L-cad')]:
			receipt = accepted['compiler_and_application_suites'][name]
			assert digest(retained / directory / 'meson-logs/testlog.json') == receipt['testlog_sha256']
			assert suite(retained / directory, receipt['tests'])['results'] == receipt['results']
		assert digest(retained / 'L-compiler/astrac') == accepted['compiler_and_application_suites']['L-compiler']['compiler_sha256']
		result['L'] = dict(reused='verified existing exact compiler and 13-entry application receipts/artifacts; no historical rebuild', compiler=accepted['compiler_and_application_suites']['L-compiler'], application=accepted['compiler_and_application_suites']['L-cad'])
		original = out / 'original-cad'
		result['original_source'] = extract_exact(args.cad_repository, pins['cad'], original, out / 'original-cad.tar')
		assert result['original_source']['members'] == json.loads((HERE / 'cad-members.json').read_text())
		source = out / 'P-source'
		shutil.copytree(original, source)
		run(['git', 'apply', '--directory=' + str(source.relative_to(ROOT)), HERE / 'compat/port.patch'], 'materialize')
		for source_name, name in [('compat/arguments.c', 'native/arguments.c'), ('compat/entry.astra', 'src/entry.astra')]:
			shutil.copyfile(HERE / source_name, source / name)
		manifest = json.loads((retained / 'sources/P-recipe-manifest.json').read_text())
		assert manifest['patch_sha256'] == digest(HERE / 'compat/port.patch')
		assert set(manifest['members']) == {str(path.relative_to(source)) for path in source.rglob('*') if path.is_file()}
		for name, row in manifest['members'].items():
			assert digest(source / name) == row['sha256'] and (source / name).stat().st_mode & 0o777 == int(row['mode'], 8), name
		result['P_source'] = manifest
		build = out / 'P-build'
		run(['meson', 'setup', build, source, '-Dwerror=true', '-Ddebug=false', '-Dastra_compiler=' + str(args.compiler.resolve()), '-Dargs_provider=' + str(args.args_provider.resolve()), '-Dreference_data=' + str(retained / 'assets')], 'P-setup')
		run(['meson', 'compile', '-C', build, '-j8'], 'P-build')
		run(['meson', 'test', '-C', build, '--no-rebuild', '--print-errorlogs', '-j4'], 'P-suite')
		result['P'] = suite(build, 13)
		result['controls'] = controls(build, json.loads((retained / 'references/ASTRA-CAD-2-VALIDATION.json').read_text()))
		parity = compare(retained / 'L-cad/test-results', build / 'test-results')
		(out / 'native-parity.json').write_text(json.dumps(parity, indent='\t') + '\n')
		assert parity['status'] == 'EXACT_RETAINED_ARTIFACTS' and len(parity['rows']) == accepted['native_parity']['artifacts_byte_equal']
		# Verify the reused L leaves against the previously accepted parity receipt.
		prior = json.loads((retained / 'inventory/L-P-native-parity.json').read_text())
		previous = {row['identity']: row['left_sha256'] for row in prior['rows']}
		assert {row['identity']: row['left_sha256'] for row in parity['rows']} == previous
		result['native_artifacts'] = len(parity['rows'])
		result['compiler_sha256'] = digest(args.compiler)
		run([sys.executable, HERE / 'allocation_failure_boundary.py', '--compiler', args.compiler, '--args-provider', args.args_provider, '--cad-repository', args.cad_repository, '--original-program', retained / 'L-cad/astra-cad', '--original-input', retained / 'L-cad/test-results/Errors/allocation-input.png', '--output', out / 'boundary'], 'boundary')
		result['status'] = 'P_AND_EXACT_CAD_PROTOCOL_PASS'
		result['scope'] = 'All original 13 P entries, 37 controls and 20560 native artifact comparisons; concrete/generic compiler boundary matrices qualify separately; no I migration or performance claim.'
	finally:
		(out / 'result.json').write_text(json.dumps(result, indent='\t') + '\n')
	return 0


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler', type=Path, required=True)
	parser.add_argument('--args-provider', type=Path, required=True)
	parser.add_argument('--cad-repository', type=Path, required=True)
	parser.add_argument('--retained-root', type=Path, required=True)
	parser.add_argument('--output', type=Path, required=True)
	sys.exit(qualify(parser.parse_args()))
