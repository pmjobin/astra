#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Measure complete owner-factory inventories under the unchanged verifier budget."""
import argparse
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

from run import BASE, C0_SHA256, ROOT, WORK, git, sha, write


def program(count):
	lines = ['class FactoryElement { int value; init(int value) { this.value = value; } }']
	for index in range(count):
		lines += [f'owned FactoryElement factory_{index}(int value) {{', '\tint padding = value;']
		lines += ['\tpadding = padding + 0;'] * 8
		lines += ['\tvar result = new FactoryElement(padding);', '\treturn move result;', '}']
	lines += [f'int main() {{ var result = factory_{count - 1}(42); return result.value; }}']
	return '\n'.join(lines) + '\n'


def reservation_program(count):
	lines = ['int reservation_later(bool fail) throws Error { if (fail) { throw new Error("reservation kept"); } return 40; }', 'int reservation_take(owned int[] values, int extra) { return len(values) + extra; }']
	for index in range(count):
		lines += [f'int reservation_case_{index}(bool fail) {{', '\tvar values = new int[2];', '\ttry {', '\t\treturn reservation_take(move values, reservation_later(fail));', '\t} catch (Error caught) {', '\t\tif (caught.message != "reservation kept") return 1;', '\t\treturn reservation_take(move values, 40);', '\t}', '}']
	lines += [f'int main() {{ if (reservation_case_{count - 1}(false) != 42) return 2; return reservation_case_{count - 1}(true); }}']
	return '\n'.join(lines) + '\n'


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler', type=Path, required=True)
	parser.add_argument('--component', type=Path)
	parser.add_argument('--build-root', type=Path, required=True)
	parser.add_argument('--runtime-root', type=Path, required=True)
	parser.add_argument('--version', required=True)
	parser.add_argument('--scope', choices=('factories', 'reservations'), default='factories')
	parser.add_argument('--phase', choices=('prepare', 'check'), required=True)
	args = parser.parse_args()
	assert args.version.isalnum() and sha(args.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	for path, parent in ((args.build_root, WORK / 'build'), (args.runtime_root, WORK / 'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
	leaf = args.runtime_root / (('owner-scaling-' if args.scope == 'factories' else 'owner-reservations-') + args.version)
	build = args.build_root / leaf.name
	if args.phase == 'prepare':
		leaf.mkdir()
		build.mkdir()
		assert args.component is None
		output = leaf
		working = build
	else:
		assert args.component and args.component.resolve().is_relative_to((WORK / 'build').resolve())
		identity = json.loads(args.component.with_suffix('.identity.json').read_text())
		assert sha(args.component) == identity['sha256']
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
		output = leaf / ('check-' + sha(args.component)[:16])
		working = build / output.name
		output.mkdir()
		working.mkdir()
	commands = []
	environment = dict(os.environ, CCACHE_DISABLE='1')
	for key in ('LD_PRELOAD', 'VALGRIND_OPTS'):
		environment.pop(key, None)

	def run(name, argv, expected=0):
		argv = list(map(str, argv))
		started = time.monotonic()
		out = output / (name + '.stdout')
		err = output / (name + '.stderr')
		timed_out = False
		with out.open('wb') as stdout, err.open('wb') as stderr:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(output / (name + '.time')), *argv], cwd=working, stdout=stdout, stderr=stderr, env=environment, start_new_session=True)
			try:
				process.wait(timeout=300)
			except subprocess.TimeoutExpired:
				timed_out = True
				os.killpg(process.pid, signal.SIGKILL)
				process.wait()
		commands.append(dict(name=name, argv=argv, exit=process.returncode, timed_out=timed_out, seconds=time.monotonic() - started, stdout_sha256=sha(out), stderr_sha256=sha(err), time_sha256=sha(output / (name + '.time'))))
		write(output / 'commands.json', commands)
		assert not timed_out and (expected is None or process.returncode == expected), (name, process.returncode, err.read_bytes()[-1800:])
		return process.returncode, out.read_bytes(), err.read_bytes()

	def memory(name, target):
		_, _, stderr = run(name, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], 42)
		assert all(marker in stderr for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))

	if args.phase == 'prepare':
		programs = []
		errors = None
		if args.scope == 'reservations':
			errors = leaf / 'errors.astra'
			errors.write_bytes(git('show', BASE + ':lib/astra/base/errors.astra'))
			errors.chmod(0o444)
		for count in (32, 768):
			source = leaf / (f'{args.scope}-{count}.astra')
			source.write_text(program(count) if args.scope == 'factories' else reservation_program(count))
			source.chmod(0o444)
			inputs = [source] if errors is None else [source, errors]
			profiles = []
			for mode in ('O0', 'O2'):
				label = f'{args.scope}-{count}-C0-{mode}'
				target = build / label
				run(label + '-build', [args.compiler, '-' + mode, *inputs, '-o', target])
				run(label + '-execute', [target], 42)
				memory(label + '-memory', target)
				profiles.append(dict(profile=mode, ELF_sha256=sha(target), execution=42, unsuppressed_memory=True))
			programs.append({args.scope:count, 'inputs':{str(path):sha(path) for path in inputs}, 'C0_profiles':profiles})
		write(leaf / 'oracles.json', dict(status='C0_OWNER_SCALING_ORACLES', programs=programs, recipe_sha256=sha(__file__), full_original_native_credit=0))
		return
	oracles = json.loads((leaf / 'oracles.json').read_text())
	providers = [args.component.parent / (name + '.o') for name in ('args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap')]
	observations = []
	for oracle in oracles['programs']:
		count = oracle[args.scope]
		label = f'{args.scope}-{count}'
		assert all(sha(path) == expected for path, expected in oracle['inputs'].items())
		row = {args.scope:count, 'inputs':oracle['inputs'], 'products':[]}
		observations.append(row)
		try:
			physical = working / (label + '.ll')
			sentinel = b'Owner factory scaling output sentinel\n'
			physical.write_bytes(sentinel)
			code, stdout, _ = run(label + '-native', [args.component, '--native', physical, *oracle['inputs']], None)
			row['native_exit'] = code
			if code:
				assert physical.read_bytes() == sentinel
				row.update(status='REFUSED', sentinel_preserved=True)
			else:
				assert b'RECOVER_SSA_VALID' in stdout and b'RECOVER_LLVM_WRITTEN' in stdout
				definitions = re.findall(r'^define internal fastcc .* @(astra\.e25a\.f\.[0-9]+)\(', physical.read_text(), re.M)
				assert len(definitions) == count + (1 if args.scope == 'factories' else 2)
				row.update(raw_LLVM_sha256=sha(physical), raw_source_functions=len(definitions) + 1)
				for mode in ('O0', 'O2'):
					prefix = label + '-' + mode
					optimized = working / (prefix + '.ll')
					obj = working / (prefix + '.o')
					target = working / prefix
					run(prefix + '-verify', ['opt', '-passes=verify', '-disable-output', physical])
					run(prefix + '-optimize', ['opt', '-passes=default<' + mode + '>', '-S', physical, '-o', optimized])
					run(prefix + '-optimized-verify', ['opt', '-passes=verify', '-disable-output', optimized])
					run(prefix + '-object', ['llc', '-filetype=obj', '-' + mode, optimized, '-o', obj])
					run(prefix + '-link', ['cc', '-no-pie', obj, *providers, '-o', target])
					run(prefix + '-execute', [target], 42)
					memory(prefix + '-memory', target)
					row['products'].append(dict(profile=mode, ELF_sha256=sha(target), object_sha256=sha(obj), optimized_LLVM_sha256=sha(optimized), execution=42, unsuppressed_memory=True))
				if args.scope == 'reservations':
					_, controls, _ = run(label + '-controls', [args.component, '--reservation-controls', *oracle['inputs']], 42)
					assert b'RESERVATION_CONTROLS count=1 order=1 operation=1 owner=1 restored=1' in controls
					row['restored_owner_controls'] = 4
				row['status'] = 'FOCUSED_OWNER_SCALING_PASS'
		except (AssertionError, OSError, subprocess.SubprocessError) as error:
			row.update(status='CHECK_FAILED', error=repr(error))
		write(output / 'result.json', dict(status='RAW_OWNER_SCALING_OBSERVATIONS', component_sha256=sha(args.component), recipe_sha256=sha(__file__), programs=observations, full_original_native_credit=0, scope='All generated bodies pass retained Source/Core/CFG/SSA and appear in raw LLVM. Linked execution exercises the final function. Reservation inputs execute both commit and abort with handler reuse. Per-function retention in optimized objects and whole-original compiler qualification require separate evidence.'))
		print(label, row['status'], flush=True)


if __name__ == '__main__':
	main()
