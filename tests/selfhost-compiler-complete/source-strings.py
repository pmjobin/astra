#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Qualify literal-result and caller-owned string-table call arguments."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, git, sha, write


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler', type=Path, required=True)
	parser.add_argument('--component', type=Path)
	parser.add_argument('--reference-host', type=Path, required=True)
	parser.add_argument('--build-root', type=Path, required=True)
	parser.add_argument('--runtime-root', type=Path, required=True)
	parser.add_argument('--version', required=True)
	parser.add_argument('--phase', choices=('prepare', 'check'), required=True)
	args = parser.parse_args()
	assert args.version.isalnum() and sha(args.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((args.build_root, WORK / 'build'), (args.runtime_root, WORK / 'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	identity = json.loads(args.reference_host.with_suffix('.identity.json').read_text())
	assert sha(args.reference_host) == identity['sha256']
	providers = [args.reference_host.parent / (name + '.o') for name in ('args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap')]
	for provider in providers:
		assert identity['identity']['sources'][str(provider)] == sha(provider)
	leaf = args.runtime_root / ('source-strings-' + args.version)
	build = args.build_root / leaf.name
	if args.phase == 'prepare':
		assert args.component is None
		leaf.mkdir()
		build.mkdir()
		revision = git('rev-parse', 'HEAD').decode().strip()
		files = {}
		for name in ('source-string-arguments.astra', 'source-string-arguments-driver.c'):
			relative = 'tests/selfhost-compiler-complete/' + name
			raw = git('show', revision + ':' + relative)
			assert (ROOT / relative).read_bytes() == raw
			path = leaf / name
			path.write_bytes(raw)
			path.chmod(0o444)
			files[str(path)] = sha(path)
		driver = leaf / 'C0-main.astra'
		driver.write_text('int main(string[] values) { return source_argument_paths(values); }\n')
		driver.chmod(0o444)
		write(leaf / 'inputs.json', dict(revision=revision, files=files, C0_driver={str(driver): sha(driver)}, providers={str(path): sha(path) for path in providers}, recipe_sha256=sha(__file__)))
		output = leaf
		working = build
	else:
		assert args.component
		component = json.loads(args.component.with_suffix('.identity.json').read_text())
		assert sha(args.component) == component['sha256']
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in component['identity'][group].items())
		output = leaf / ('check-' + sha(args.component)[:16])
		working = build / output.name
		output.mkdir()
		working.mkdir()
	manifest = json.loads((leaf / 'inputs.json').read_text())
	assert all(sha(path) == expected for group in ('files', 'C0_driver', 'providers') for path, expected in manifest[group].items())
	source = leaf / 'source-string-arguments.astra'
	driver = leaf / 'C0-main.astra'
	commands = []
	environment = dict(os.environ, CCACHE_DISABLE='1')
	for key in ('LD_PRELOAD', 'VALGRIND_OPTS'):
		environment.pop(key, None)

	def run(name, command, expected=0):
		argv = list(map(str, command))
		started = time.monotonic()
		stdout = output / (name + '.stdout')
		stderr = output / (name + '.stderr')
		with stdout.open('wb') as out, stderr.open('wb') as err:
			process = subprocess.run(['/usr/bin/time', '-v', '-o', str(output / (name + '.time')), *argv], cwd=working, stdout=out, stderr=err, env=environment, timeout=300)
		commands.append(dict(name=name, argv=argv, exit=process.returncode, seconds=time.monotonic() - started, stdout_sha256=sha(stdout), stderr_sha256=sha(stderr), time_sha256=sha(output / (name + '.time'))))
		write(output / 'commands.json', commands)
		assert expected is None or process.returncode == expected, (name, process.returncode, stderr.read_bytes()[-1600:])
		return process.returncode, stdout.read_bytes(), stderr.read_bytes()

	def execute(name, target):
		_, stdout, stderr = run(name + '-execute', [target, 'A', 'ASTRA'], 42)
		assert stdout == stderr == b''
		_, stdout, stderr = run(name + '-empty', [target], 1)
		assert stdout == stderr == b''
		_, _, memory = run(name + '-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target, 'A', 'ASTRA'], 42)
		assert all(value in memory for value in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		_, _, empty_memory = run(name + '-empty-memory', ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], 1)
		assert all(value in empty_memory for value in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		return dict(ELF_sha256=sha(target), execution=42, short_input_execution=1, unsuppressed_memory=True)

	if args.phase == 'prepare':
		_, semantics, _ = run('C0-semantics', [args.compiler, '--dump-semantics', source, driver])
		names = re.findall(rb'^\t\(function "([^"]+)"', semantics, re.M)
		assert names.count(b'main') == 1
		assert [name for name in names if name != b'main'] == [b'source_argument_literal', b'source_argument_length', b'source_argument_paths']
		profiles = []
		for mode in ('O0', 'O2'):
			target = working / ('C0-' + mode)
			run(mode + '-build', [args.compiler, '-' + mode, source, driver, '--link-object', providers[0], '-o', target])
			profiles.append(dict(profile=mode, **execute(mode, target)))
		write(leaf / 'oracles.json', dict(status='C0_SOURCE_STRING_ARGUMENT_ORACLES', profiles=profiles, inputs_manifest_sha256=sha(leaf / 'inputs.json'), target_native_credit=0))
		return
	oracles = json.loads((leaf / 'oracles.json').read_text())
	assert oracles['inputs_manifest_sha256'] == sha(leaf / 'inputs.json')
	assert [row['profile'] for row in oracles['profiles']] == ['O0', 'O2']
	assert all(row['execution'] == 42 and row['short_input_execution'] == 1 and row['unsuppressed_memory'] for row in oracles['profiles'])
	physical = working / 'source-strings.ll'
	sentinel = b'Source string argument output sentinel\n'
	physical.write_bytes(sentinel)
	code, stdout, _ = run('Astra-native', [args.component, '--native-module', physical, source], None)
	result = dict(component_sha256=sha(args.component), inputs_manifest_sha256=sha(leaf / 'inputs.json'), native_exit=code, profiles=[], whole_original_native_credit=0)
	if code:
		assert physical.read_bytes() == sentinel
		result.update(status='REFUSED', sentinel_preserved=True)
	else:
		assert b'RECOVER_SSA_VALID' in stdout and b'RECOVER_LLVM_WRITTEN' in stdout
		raw = physical.read_text()
		functions = re.findall(r'^define internal fastcc .* @(astra\.e25a\.f\.[0-9]+)\(', raw, re.M)
		assert len(functions) == 3 and len(set(functions)) == 3
		assert re.search(r'^define internal fastcc i32 @' + re.escape(functions[-1]) + r'\(ptr [^,]+, i32 [^)]+\)', raw, re.M)
		run('Astra-verify', ['opt', '-passes=verify', '-disable-output', physical])
		bridge = working / 'source-strings-with-bridge.ll'
		bridge.write_text(raw + '\ndefine i32 @m26_source_strings(ptr %values, i32 %count) {\nentry:\n  %result = call fastcc i32 @' + functions[-1] + '(ptr %values, i32 %count)\n  ret i32 %result\n}\n')
		for mode in ('O0', 'O2'):
			optimized = working / (mode + '.ll')
			obj = working / (mode + '.o')
			target = working / ('Astra-' + mode)
			run(mode + '-bridge-verify', ['opt', '-passes=verify', '-disable-output', bridge])
			run(mode + '-optimize', ['opt', '-passes=default<' + mode + '>', '-S', bridge, '-o', optimized])
			run(mode + '-optimized-verify', ['opt', '-passes=verify', '-disable-output', optimized])
			run(mode + '-object', ['llc', '-filetype=obj', '-' + mode, optimized, '-o', obj])
			run(mode + '-link', ['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-no-pie', obj, leaf / 'source-string-arguments-driver.c', *providers, '-o', target])
			result['profiles'].append(dict(profile=mode, object_sha256=sha(obj), optimized_LLVM_sha256=sha(optimized), **execute(mode, target)))
		result.update(status='SOURCE_STRING_ARGUMENT_NATIVE_PASS', raw_LLVM_sha256=sha(physical), authored_bridge_LLVM_sha256=sha(bridge), retained_source_functions=3, bridge_scope='The authored C ABI entry forwards the caller-owned descriptor table to the real Astra-produced private function. Raw production LLVM is independently verified before appending the test entry.')
	write(output / 'result.json', result)


if __name__ == '__main__':
	main()
