#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Link every original compiler input into a compiler-service application."""
import argparse
import ast
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
from threading import RLock
import time

from run import BASE, C0_SHA256, ROOT, WORK, git, sha, write


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--compiler', type=Path, required=True)
	parser.add_argument('--reference-host', type=Path, required=True)
	parser.add_argument('--component', type=Path)
	parser.add_argument('--build-root', type=Path, required=True)
	parser.add_argument('--runtime-root', type=Path, required=True)
	parser.add_argument('--version', required=True)
	parser.add_argument('--phase', choices=('prepare', 'check'), required=True)
	args = parser.parse_args()
	assert args.version.isalnum() and sha(args.compiler) == C0_SHA256
	assert subprocess.check_output(['llvm-config', '--version']).strip() == b'23.1.4'
	assert sha('/usr/lib64/libLLVM.so.23.1') == '3149b73c3118dee2d2829a210b422ca89a4aa0064b57e77936ede12bdcfe750d'
	for path, parent in ((args.build_root, WORK / 'build'), (args.runtime_root, WORK / 'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve()) and path.is_dir()
		assert all(not entry.is_symlink() for entry in (path, *path.parents))
	host_identity = json.loads(args.reference_host.with_suffix('.identity.json').read_text())
	assert sha(args.reference_host) == host_identity['sha256']
	assert all(sha(path) == expected for path, expected in host_identity['identity']['tools'].items())
	reference_snapshot = json.loads((args.runtime_root / args.reference_host.parent.name / 'snapshot.json').read_text())
	historical_recipes = []
	for name, expected in host_identity['identity']['sources'].items():
		path = Path(name)
		if sha(path) != expected:
			assert path.parent == ROOT / 'tests/selfhost-compiler-complete' and path.name in ('native-build.py', 'run.py', 'compile-plan.py')
			relative = str(path.relative_to(ROOT))
			raw = git('show', reference_snapshot['revision'] + ':' + relative)
			assert hashlib.sha256(raw).hexdigest() == expected
			historical_recipes.append(dict(path=name, sha256=expected, Git_revision=reference_snapshot['revision'], Git_blob=git('rev-parse', reference_snapshot['revision'] + ':' + relative).decode().strip()))
	command = host_identity['identity']['argv']
	links = command[command.index('--link-object'):command.index('-o')]
	objects = [Path(links[i + 1]) for i, value in enumerate(links) if value == '--link-object']
	libraries = [links[i + 1] for i, value in enumerate(links) if value == '--link-library']
	assert len(objects) == 6 and len(libraries) == 1
	providers = [path for path in objects if path.name != 'llvm-capi.o']
	assert len(providers) == 5
	tools = dict(host_identity['identity']['tools'])
	for name in ('opt', 'llc', 'cc', 'readelf', 'nm', 'valgrind'):
		path = Path(shutil.which(name)).resolve(strict=True)
		tools[str(path)] = sha(path)
		for word in subprocess.run(['ldd', path], capture_output=True, text=True).stdout.split():
			if word.startswith('/') and Path(word).is_file():
				dependency = Path(word).resolve()
				tools[str(dependency)] = sha(dependency)
	leaf = args.runtime_root / ('representative-use-' + args.version)
	build = args.build_root / leaf.name
	if args.phase == 'prepare':
		assert args.component is None
		leaf.mkdir()
		build.mkdir()
		output = leaf
		working = build
		revision = git('rev-parse', 'HEAD').decode().strip()
		fixture = 'tests/selfhost-compiler-complete/representative-compiler-use.astra'
		raw = git('show', revision + ':' + fixture)
		assert (ROOT / fixture).read_bytes() == raw
		entry = leaf / Path(fixture).name
		entry.write_bytes(raw)
		entry.chmod(0o444)
		names = [name for name in git('ls-tree', '-r', '--name-only', BASE, 'compiler').decode().splitlines() if name.endswith('.astra')]
		model = ast.parse(git('show', BASE + ':tests/selfhost-typecore/build.py').decode())
		dependencies = next(ast.literal_eval(node.value) for node in model.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'LIBRARIES' for target in node.targets))
		assert len(names) == 180 and len(dependencies) == 10
		names += ['lib/astra/' + name + '.astra' for name in dependencies]
		inputs = {}
		for name in names:
			path = leaf / 'original-inputs' / name
			path.parent.mkdir(parents=True, exist_ok=True)
			path.write_bytes(git('show', BASE + ':' + name))
			path.chmod(0o444)
			inputs[str(path)] = sha(path)
		inputs[str(entry)] = sha(entry)
		manifest = dict(baseline=BASE, fixture_revision=revision, fixture=str(entry), inputs=inputs, original_compiler_files=180, original_library_files=10, tools=tools, link_objects={str(path):sha(path) for path in objects}, link_libraries=libraries, recipe_sha256=sha(__file__), reference_host_sha256=sha(args.reference_host), scope='All original compiler inputs plus one Astra application entry. The application compiles a representative integer program. Compiler self-hosting cycles have separate authorization.')
		write(leaf / 'inputs.json', manifest)
		(leaf / 'recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	else:
		assert args.component and args.component.resolve().is_relative_to((WORK / 'build').resolve())
		identity = json.loads(args.component.with_suffix('.identity.json').read_text())
		assert sha(args.component) == identity['sha256']
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
		manifest = json.loads((leaf / 'inputs.json').read_text())
		inputs = manifest['inputs']
		assert manifest['tools'] == tools and manifest['link_objects'] == {str(path):sha(path) for path in objects}
		assert len(inputs) == 191 and all(sha(path) == expected and Path(path).stat().st_mode & 0o222 == 0 for path, expected in inputs.items())
		output = leaf / ('check-' + sha(args.component)[:16])
		working = build / output.name
		output.mkdir()
		working.mkdir()
	commands = []
	lock = RLock()
	environment = dict(os.environ, CCACHE_DISABLE='1')
	for key in ('LD_PRELOAD', 'VALGRIND_OPTS'):
		environment.pop(key, None)

	def run(name, argv, directory, expected=0, timeout=300):
		argv = list(map(str, argv))
		started = time.monotonic()
		out = output / (name + '.stdout')
		err = output / (name + '.stderr')
		timed_out = False
		with out.open('wb') as stdout, err.open('wb') as stderr:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(output / (name + '.time')), *argv], cwd=directory, stdout=stdout, stderr=stderr, env=environment, start_new_session=True)
			try:
				process.wait(timeout=timeout)
			except subprocess.TimeoutExpired:
				timed_out = True
				os.killpg(process.pid, signal.SIGKILL)
				process.wait()
		with lock:
			commands.append(dict(name=name, argv=argv, cwd=str(directory), exit=process.returncode, timed_out=timed_out, seconds=time.monotonic() - started, stdout_sha256=sha(out), stderr_sha256=sha(err), time_sha256=sha(output / (name + '.time'))))
			write(output / 'commands.json', commands)
		print(name, process.returncode, flush=True)
		assert not timed_out and (expected is None or process.returncode == expected), (name, process.returncode, err.read_bytes()[-1800:])
		return process.returncode, out.read_bytes(), err.read_bytes()

	def memory(name, target, directory):
		_, _, stderr = run(name, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', target], directory, 42, 900)
		assert all(marker in stderr for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))

	def execute_application(label, target, directory, mode):
		_, stdout, stderr = run(label + '-execute', [target], directory, 42)
		generated = directory / 'm26-representative.ll'
		assert generated.is_file()
		digest = sha(generated)
		memory(label + '-memory', target, directory)
		assert sha(generated) == digest
		optimized = directory / 'representative-optimized.ll'
		obj = directory / 'representative.o'
		program = directory / 'representative-program'
		run(label + '-generated-verify', ['opt', '-passes=verify', '-disable-output', generated], directory)
		run(label + '-generated-optimize', ['opt', '-passes=default<' + mode + '>', '-S', generated, '-o', optimized], directory)
		run(label + '-generated-optimized-verify', ['opt', '-passes=verify', '-disable-output', optimized], directory)
		run(label + '-generated-object', ['llc', '-filetype=obj', '-' + mode, optimized, '-o', obj], directory)
		run(label + '-generated-link', ['cc', '-no-pie', obj, *providers, '-o', program], directory)
		run(label + '-generated-execute', [program], directory, 42)
		memory(label + '-generated-memory', program, directory)
		_, header, _ = run(label + '-ELF', ['readelf', '-h', target], directory)
		assert b'ELF64' in header and b'X86-64' in header
		return dict(profile=mode, ELF_sha256=sha(target), execution=42, unsuppressed_memory=True, stdout_sha256=hashlib.sha256(stdout).hexdigest(), stderr_sha256=hashlib.sha256(stderr).hexdigest(), generated_LLVM_sha256=digest, generated_object_sha256=sha(obj), generated_ELF_sha256=sha(program), generated_execution=42, generated_unsuppressed_memory=True)

	if args.phase == 'prepare':
		def reference(mode):
			directory = working / mode
			directory.mkdir()
			target = directory / 'C0-compiler-use'
			label = 'C0-' + mode
			run(label + '-build', [args.compiler, '-' + mode, *inputs, *links, '-o', target], directory, timeout=7200)
			assert all(sha(path) == expected for path, expected in inputs.items())
			return execute_application(label, target, directory, mode)
		with ThreadPoolExecutor(max_workers=2) as pool:
			profiles = list(pool.map(reference, ('O0', 'O2')))
		assert all(sha(path) == expected for path, expected in tools.items())
		write(leaf / 'oracles.json', dict(status='C0_ORIGINAL_COMPILER_USAGE_ORACLES', profiles=profiles, manifest_sha256=sha(leaf / 'inputs.json'), Astra_native_credit=0))
		return
	oracles = json.loads((leaf / 'oracles.json').read_text())
	assert oracles['manifest_sha256'] == sha(leaf / 'inputs.json')
	physical = working / 'compiler-use.ll'
	sentinel = b'Full original compiler application output sentinel\n'
	physical.write_bytes(sentinel)
	code, stdout, _ = run('Astra-native', [args.component, '--native', physical, *inputs], working, None, 1800)
	result = dict(component_sha256=sha(args.component), inputs_manifest_sha256=sha(leaf / 'inputs.json'), native_exit=code, profiles=[], historical_reference_recipes=historical_recipes, full_original_library_object_qualification=0)
	if code:
		assert physical.read_bytes() == sentinel
		result.update(status='REFUSED', sentinel_preserved=True)
	else:
		assert b'RECOVER_SSA_VALID' in stdout and b'RECOVER_LLVM_WRITTEN' in stdout
		for mode in ('O0', 'O2'):
			directory = working / mode
			directory.mkdir()
			label = 'Astra-' + mode
			optimized = directory / 'compiler-use-optimized.ll'
			obj = directory / 'compiler-use.o'
			target = directory / 'Astra-compiler-use'
			run(label + '-verify', ['opt', '-passes=verify', '-disable-output', physical], directory)
			run(label + '-optimize', ['opt', '-passes=default<' + mode + '>', '-S', physical, '-o', optimized], directory)
			run(label + '-optimized-verify', ['opt', '-passes=verify', '-disable-output', optimized], directory)
			run(label + '-object', ['llc', '-filetype=obj', '-' + mode, optimized, '-o', obj], directory)
			run(label + '-link', ['cc', '-no-pie', obj, *objects, *['-l' + name for name in libraries], '-o', target], directory)
			profile = execute_application(label, target, directory, mode)
			oracle = next(row for row in oracles['profiles'] if row['profile'] == mode)
			assert all(profile[key] == oracle[key] for key in ('stdout_sha256', 'stderr_sha256', 'generated_LLVM_sha256'))
			profile.update(object_sha256=sha(obj), optimized_LLVM_sha256=sha(optimized))
			result['profiles'].append(profile)
		result['status'] = 'LINKED_ORIGINAL_COMPILER_USAGE_PASS'
	assert all(sha(path) == expected for path, expected in tools.items())
	write(output / 'result.json', result)


if __name__ == '__main__':
	main()
