#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Stage, relocate and consume the complete I application through public astrac."""
import argparse
import hashlib
import itertools
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]


def digest(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def install(args):
	out = args.output.resolve()
	out.mkdir(parents=True, exist_ok=False)
	(out / 'tmp').mkdir()
	env = dict(os.environ, CC='/usr/bin/gcc', CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1', TMPDIR=str(out / 'tmp'))
	commands = []
	def run(command, label, cwd=ROOT, expected=0, extra=None):
		command = list(map(str, command))
		process = subprocess.run(command, cwd=cwd, env=env | (extra or {}), capture_output=True)
		(out / (label + '.stdout')).write_bytes(process.stdout)
		(out / (label + '.stderr')).write_bytes(process.stderr)
		commands.append({'argv': command, 'cwd': str(cwd), 'label': label, 'status': process.returncode, 'expected': expected})
		(out / 'commands.json').write_text(json.dumps(commands, indent='\t') + '\n')
		assert process.returncode == expected, commands[-1]
		return process
	build = args.compiler_build.resolve()
	options = {row['name']: row['value'] for row in json.loads((build / 'meson-info/intro-buildoptions.json').read_text())}
	configured = Path(options['prefix'])
	assert configured.is_relative_to(ROOT / 'build/app-cad-2') and not Path(options['libdir']).is_absolute()
	run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', out / 'stage'], 'install')
	prefix = out / 'relocated-prefix'
	shutil.move(out / 'stage' / str(configured).lstrip('/'), prefix)
	compiler = prefix / 'bin/astrac'
	provider = prefix / options['libdir'] / 'astra/x86_64-linux/args-posix.o'
	assert digest(compiler) == digest(build / 'astrac') and digest(provider) == digest(build / 'lib/astra/args-posix.o')
	manifest = {str(path.relative_to(prefix)): {'sha256': digest(path), 'bytes': path.stat().st_size, 'mode': path.stat().st_mode & 0o777} for path in sorted(prefix.rglob('*')) if path.is_file()}
	(out / 'installed-members.json').write_text(json.dumps(manifest, indent='\t') + '\n')
	source = out / 'consumer'
	shutil.copytree(args.source.resolve(), source)
	application = out / 'application'
	run(['meson', 'setup', application, source, '-Dwerror=true', '-Ddebug=false', '-Dastra_compiler=' + str(compiler), '-Dargs_provider=' + str(provider), '-Dreference_data=' + str(args.assets.resolve())], 'consumer-setup', source)
	run(['meson', 'compile', '-C', application, '-j2'], 'consumer-build', source)
	identities = {}
	for name in ['astra-cad', 'numeric-tests', 'algorithm-tests', 'step-tests', 'orientation-tests', 'libcad-io.so', 'libcad-test-io.so']:
		assert digest(application / name) == digest(args.reference_build / name), name
		identities[name] = digest(application / name)
	files = ['src/numeric.astra', 'src/algorithm.astra', 'src/main.astra', 'src/entry.astra']
	stages = ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
	canonical, rows = {}, []
	for number, order in enumerate(itertools.permutations(files)):
		row = {'order': list(order), 'stages': {}}
		for stage in stages:
			process = run([compiler, '--dump-' + stage, *order], f'order-{number:02}-{stage}', source)
			sha = hashlib.sha256(process.stdout).hexdigest()
			if number == 0:
				canonical[stage] = sha
			assert sha == canonical[stage], (number, stage)
			row['stages'][stage] = sha
		target = application / f'order-{number:02}'
		run([compiler, *order, '--link-object', application / 'libcad-io.so', '--link-object', provider, '-o', target], f'order-{number:02}-compile', source)
		assert digest(target) == identities['astra-cad']
		row['executable_sha256'] = digest(target)
		run([sys.executable, '-B', ROOT / 'workloads/cad/smoke.py', '--program', target, '--output', out / f'smoke-{number:02}'], f'order-{number:02}-smoke', source)
		rows.append(row)
		(out / 'permutations.json').write_text(json.dumps(rows, indent='\t') + '\n')
		# The entire application remains present; these are the actual four Astra
		# production sources, plus its independently rebuilt C adapter and ARGS object.
	run(['meson', 'test', '-C', application, '--no-rebuild', '--print-errorlogs', '-j2', 'numeric-foundation', 'algorithm-foundation', 'analytical', 'errors', 'corrections', 'symmetry'], 'selected-original-tests', source)
	# Missing/duplicate object errors must preserve an already existing output.
	guard = out / 'existing-output'
	guard.write_bytes(b'preserve this output on link error\n')
	before = digest(guard)
	duplicate = out / 'duplicate-args.o'
	shutil.copyfile(provider, duplicate)
	for label, links in [('missing-args', ['--link-object', application / 'libcad-io.so']), ('missing-adapter', ['--link-object', provider]), ('duplicate-args', ['--link-object', application / 'libcad-io.so', '--link-object', provider, '--link-object', duplicate])]:
		run([compiler, *files, *links, '-o', guard], label, source, expected=1)
		assert digest(guard) == before, label
	result = {'status': 'INSTALLED_I_REPLAY_PASS', 'configured_prefix': str(configured), 'datadir': options['datadir'], 'libdir': options['libdir'], 'relocated_prefix': str(prefix), 'compiler_sha256': digest(compiler), 'explicit_provider': str(provider), 'provider_sha256': digest(provider), 'selected_source_libraries': [], 'source_library_reason': 'I preserves the original scalar libm/conversion interface and uses direct public native arrays; no source library is needed by this consumer.', 'full_application_artifacts': identities, 'orders': len(rows), 'canonical_stages': canonical, 'receipt_reuse': 'Full original acceptance attaches to these exact seven byte-identical application artifacts and unchanged input/dependency identities. The 24 smokes and selected original replay are separate, not 24 full suites.'}
	(out / 'result.json').write_text(json.dumps(result, indent='\t') + '\n')
	print(json.dumps({key: result[key] for key in ['status', 'orders', 'configured_prefix', 'datadir', 'libdir', 'relocated_prefix']}))


if __name__ == '__main__':
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['compiler-build', 'source', 'reference-build', 'assets', 'output']:
		parser.add_argument('--' + name, type=Path, required=True)
	install(parser.parse_args())
