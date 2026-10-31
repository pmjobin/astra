# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Real optional Linux installation and relocated four-user-source consumer."""
import hashlib
import itertools
import json
import re
from pathlib import Path
import shutil
import subprocess
import sys

SOURCE = Path(__file__).resolve().parents[2]

def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
	build, helper, output = [Path(value).resolve() for value in sys.argv[1:4]]
	output.mkdir(parents=True, exist_ok=True)
	current = output / 'current'
	owner = {'purpose': 'L1 optional staged and relocated installation', 'source': str(SOURCE)}
	if current.exists():
		assert not current.is_symlink() and json.loads((current / 'owner.json').read_text()) == owner
		prior = current / 'receipts.json'
		if prior.exists():
			history = output / 'history'
			history.mkdir(exist_ok=True)
			(history / (sha(prior) + '.json')).write_bytes(prior.read_bytes())
		shutil.rmtree(current)
	current.mkdir()
	(current / 'owner.json').write_text(json.dumps(owner) + '\n')
	records = []
	identity = {'compiler_sha256': sha(build / 'astrac'), 'records': records, 'orders': 24, 'user_sources': 4, 'helper_library_sha256': sha(helper / 'lib/liburing.a')}
	def save():
		(current / 'receipts.json').write_text(json.dumps(identity, separators=(',', ':')) + '\n')
	def run(name, command, expected=0, cwd=None, expected_stdout=None, diagnostic=None):
		command = list(map(str, command))
		result = subprocess.run(command, cwd=cwd, capture_output=True, timeout=90)
		row = {'name': name, 'command': command, 'cwd': str(cwd), 'expected': expected, 'exit': result.returncode, 'stdout_sha256': hashlib.sha256(result.stdout).hexdigest(), 'stderr_sha256': hashlib.sha256(result.stderr).hexdigest(), 'status': 'PASS' if result.returncode == expected and (expected_stdout is None or result.stdout == expected_stdout) else 'FAIL'}
		if expected != 0:
			row['diagnostic'] = result.stderr.decode(errors='replace')[-2500:]
		if diagnostic is not None and diagnostic not in result.stdout + result.stderr:
			row['status'] = 'FAIL'
		records.append(row)
		save()
		print(name, row['status'], flush=True)
		assert row['status'] == 'PASS', (command, result.returncode, result.stdout[-1000:], result.stderr[-4000:])
		return result.stdout
	options = {row['name']: row['value'] for row in json.loads(run('install-options', ['meson', 'introspect', build, '--buildoptions']))}
	stage = current / 'stage'
	run('actual-Meson-install', ['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
	prefix = stage / Path(options['prefix']).relative_to('/')
	private = prefix / 'lib/astra-private-liburing'
	shutil.copytree(helper / 'include', private / 'include')
	(private / 'lib').mkdir()
	shutil.copyfile(helper / 'lib/liburing.a', private / 'lib/liburing.a')
	(private / 'licenses').mkdir()
	license_names = ('COPYING', 'COPYING.GPL', 'LICENSE')
	notices = helper
	if not all((helper / name).is_file() for name in license_names):
		version = re.search(r'^Version:\s*(\S+)', (helper / 'lib/pkgconfig/liburing.pc').read_text(), re.M)
		assert version is not None and version[1] == '2.15', 'missing notices require the exact pinned liburing 2.15 profile'
		notices = SOURCE / 'tools/release/licenses/liburing-2.15'
		provenance = json.loads((notices / 'provenance.json').read_text())
		assert provenance['tag'] == 'liburing-2.15'
		for name in license_names:
			assert sha(notices / name) == provenance['files'][name]['sha256']
	for name in license_names:
		shutil.copyfile(notices / name, private / 'licenses' / name)
	identity['helper_license_notices'] = {name: {'source': str(notices / name), 'sha256': sha(notices / name)} for name in license_names}
	save()
	client = current / 'client'
	shutil.copytree(SOURCE / 'tests/async-io-1/application', client)
	shutil.copyfile(SOURCE / 'tests/async-io-1/observer.c', client / 'observer.c')
	canonical = None
	phases = []
	for phase in ('staged', 'relocated'):
		if phase == 'relocated':
			relocated = current / 'relocated-prefix'
			shutil.move(prefix, relocated)
			prefix = relocated
		def location(option):
			path = Path(options[option])
			return prefix / (path.relative_to(options['prefix']) if path.is_absolute() else path)
		compiler = location('bindir') / 'astrac'
		library = location('datadir') / 'astra'
		core = location('libdir') / 'astra/x86_64-linux/async-virtual.o'
		provider = core.with_name('libastra-async-linux.a')
		helper_library = prefix / 'lib/astra-private-liburing/lib/liburing.a'
		assert sha(compiler) == sha(build / 'astrac') and sha(core) == sha(build / 'lib/astra/async-virtual.o') and sha(provider) == sha(build / 'lib/astra/libastra-async-linux.a') and sha(helper_library) == identity['helper_library_sha256']
		for name in ('base/errors.astra', 'async/linux.astra', 'async/linux.c', 'async/linux.h', 'async/virtual.c', 'async/virtual.h', 'async/provider.h'):
			assert (library / name).read_bytes() == (SOURCE / 'lib/astra' / name).read_bytes()
		observer = client / 'observer.o'
		run(phase + '-consumer-observer', ['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-DASTRA_LINUX_PLAIN_OBSERVER', '-I' + str(library / 'async'), '-c', 'observer.c', '-o', observer], cwd=client)
		support = [library / 'base/errors.astra', library / 'async/linux.astra']
		sources = [Path(n) for n in ('types.astra', 'produce.astra', 'controller.astra', 'main.astra')]
		observed = run(phase + '-canonical-SSA', [compiler, '--dump-ssa', *support, *sources], cwd=client)
		if canonical is None:
			canonical = observed
		assert observed == canonical
		if phase == 'staged':
			run('Linux-missing-provider-link', [compiler, *support, *sources, '--link-object', core, '--link-object', helper_library, '--link-object', observer, '-o', client / 'program'], expected=1, cwd=client, diagnostic=b'astra_async_linux_')
		for index, order in enumerate(itertools.permutations(sources)):
			run(phase + '-SSA-order-%02d' % index, [compiler, '--dump-ssa', *support, *order], cwd=client, expected_stdout=canonical)
			program = client / 'program'
			args = [compiler, *support, *order]
			for obj in (core, provider, helper_library, observer):
				args += ['--link-object', obj]
			run(phase + '-native-order-%02d' % index, [*args, '-o', program], cwd=client)
			run(phase + '-REAL-order-%02d' % index, [program], expected=42, cwd=client)
		elf = run(phase + '-ELF-dependencies', ['readelf', '-d', program])
		needed = re.findall(rb'\(NEEDED\).*\[([^]]+)\]', elf)
		assert needed and all(b'uring' not in name and b'glib' not in name for name in needed)
		phases.append({'phase': phase, 'orders': 24, 'compiler_sha256': sha(compiler), 'core_sha256': sha(core), 'provider_sha256': sha(provider), 'helper_library_sha256': sha(helper_library), 'SSA_sha256': hashlib.sha256(canonical).hexdigest(), 'ELF_NEEDED': [name.decode() for name in needed]})
	identity.update({'status': 'PASS', 'phases': phases})
	save()
	(output / 'current.json').write_text(json.dumps({'status': 'PASS', 'receipts_sha256': sha(current / 'receipts.json')}) + '\n')
	return 0

if __name__ == '__main__':
	sys.dont_write_bytecode = True
	sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools/qualification'))
	from output_paths import fresh_output
	sys.argv[-1] = str(fresh_output(sys.argv[-1]))
	sys.exit(main())
