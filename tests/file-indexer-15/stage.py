# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Exercise copied indexer sources with the public staged compiler and library."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('build', type=Path)
	parser.add_argument('build_output', type=Path)
	parser.add_argument('runtime_output', type=Path)
	parser.add_argument('--uring-prefix', type=Path)
	args = parser.parse_args()
	build = args.build.resolve(strict=True)
	output = args.runtime_output.resolve()
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='index-installed-', dir=output))
	receipt = dict(format='astra-m15-indexer-staged/1', recipe_sha256=sha(Path(__file__)),
		compiler_sha256=sha(build / 'astrac'), checks=[], source_copies={}, qualifications=[])

	def save():
		(out / 'checks.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	def run(name, argv):
		argv = list(map(str, argv))
		started = time.perf_counter()
		result = subprocess.run(argv, cwd=out, capture_output=True, timeout=300,
			env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1', CCACHE_DISABLE='1'))
		(out / (name + '.stdout')).write_bytes(result.stdout)
		(out / (name + '.stderr')).write_bytes(result.stderr)
		receipt['checks'].append(dict(name=name, argv=argv, exit=result.returncode,
			elapsed_seconds=time.perf_counter() - started, passed=result.returncode == 0,
			stdout_sha256=hashlib.sha256(result.stdout).hexdigest(), stderr_sha256=hashlib.sha256(result.stderr).hexdigest()))
		save()
		assert result.returncode == 0, (name, result.stderr.decode(errors='replace')[-2000:])
		return result.stdout

	options = {row['name']: row['value'] for row in json.loads(run('options', ['meson', 'introspect', build, '--buildoptions']))}
	stage = out / 'stage'
	run('install', ['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
	prefix = stage / Path(options['prefix']).relative_to('/')

	def location(option):
		path = Path(options[option])
		return prefix / (path.relative_to(options['prefix']) if path.is_absolute() else path)

	compiler = location('bindir') / 'astrac'
	library = location('datadir') / 'astra'
	runtime = location('libdir') / 'astra/x86_64-linux'
	assert sha(compiler) == receipt['compiler_sha256']
	for name in ['box', 'map', 'cache']:
		installed = library / ('collections/' + name + '.astra')
		assert sha(installed) == sha(ROOT / 'lib/astra/collections' / (name + '.astra'))
	client = out / 'client/tests/file-indexer-15'
	client.mkdir(parents=True)
	for source in sorted(HERE.iterdir()):
		if source.suffix in ['.astra', '.c', '.py', '.md'] and source.name != Path(__file__).name:
			copy = client / source.name
			shutil.copy2(source, copy)
			receipt['source_copies'][str(copy)] = sha(source)
	for profile in [None, 'virtual', *(['linux'] if args.uring_prefix else [])]:
		name = profile or 'sync'
		command = ['python3', '-B', client / 'qualify.py', compiler,
			args.build_output.resolve() / out.name / name, out / 'runs' / name,
			'--library-root', library, '--runtime-root', runtime, '--read-fault-adapter']
		if profile:
			command += ['--async-profile', profile]
		if profile == 'linux':
			command += ['--uring-prefix', args.uring_prefix.resolve(strict=True)]
		path = Path(run('qualify-' + name, command).decode().strip())
		data = json.loads(path.read_text())
		assert data['all_passed'] and data['compiler_sha256'] == receipt['compiler_sha256']
		receipt['qualifications'].append(dict(profile=profile, path=str(path), sha256=sha(path),
			checks=len(data['checks']), memory=sum(c['argv'][0] == 'valgrind' for c in data['checks'])))
	assert all(sha(Path(path)) == digest for path, digest in receipt['source_copies'].items())
	assert sha(build / 'astrac') == receipt['compiler_sha256']
	receipt['all_passed'] = True
	save()
	print(out / 'checks.json')


if __name__ == '__main__':
	main()
