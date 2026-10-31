#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Two independent source/build/install runs; never labels an unqualified RC."""
from pathlib import Path
import argparse
import gzip
import hashlib
import json
import os
import select
import shutil
import signal
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
sys.dont_write_bytecode = True
from license_inventory import inventory as license_inventory

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def tree(prefix):
	result = {}
	for path in sorted(prefix.rglob('*')):
		if path.is_dir():
			continue
		assert path.is_file() and not path.is_symlink(), f'unexpected installed entry: {path}'
		result[str(path.relative_to(prefix))] = {'sha256': sha(path), 'bytes': path.stat().st_size,
			'mode': stat.S_IMODE(path.stat().st_mode)}
	return result


def archive(prefix, output, epoch):
	with output.open('xb') as raw, gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=epoch) as zipped:
		with tarfile.open(fileobj=zipped, mode='w') as tar:
			for path in sorted(prefix.rglob('*')):
				if not path.is_file():
					continue
				info = tar.gettarinfo(str(path), 'astra-dev/' + str(path.relative_to(prefix)))
				info.uid = info.gid = 0
				info.uname = info.gname = ''
				info.mtime = epoch
				with path.open('rb') as data:
					tar.addfile(info, data)


def installed_lsp_client(prefix, program, consumer, env):
	"""Await real responses before shutdown, within the original 45 s budget."""
	command = [str(prefix / 'bin/astra-lsp')]
	responses, wire = [], bytearray()
	deadline = time.monotonic() + 45
	with (consumer / 'lsp.stderr').open('wb') as errors:
		process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
			stderr=errors, cwd=consumer, env=env, start_new_session=True)
		pending = bytearray()
		def send(request):
			body = json.dumps({'jsonrpc': '2.0', **request}).encode()
			process.stdin.write(f'Content-Length: {len(body)}\r\n\r\n'.encode() + body)
			process.stdin.flush()
		def read_more():
			remaining = deadline - time.monotonic()
			assert remaining > 0 and select.select([process.stdout], [], [], remaining)[0], 'installed LSP response deadline'
			part = os.read(process.stdout.fileno(), 65536)
			assert part, 'installed LSP closed before its response'
			pending.extend(part)
			wire.extend(part)
		def receive(request_id):
			while True:
				while b'\r\n\r\n' not in pending:
					read_more()
				header, body = bytes(pending).split(b'\r\n\r\n', 1)
				length = int(header.decode().split(':', 1)[1])
				assert 0 <= length <= 16 * 1024 * 1024
				while len(body) < length:
					read_more()
					body = bytes(pending[len(header) + 4:])
				response = json.loads(body[:length])
				del pending[:len(header) + 4 + length]
				responses.append(response)
				assert 'error' not in response, response
				if response.get('id') == request_id:
					return response
		try:
			send({'id': 1, 'method': 'initialize', 'params': {'rootUri': consumer.as_uri(), 'capabilities': {}}})
			receive(1)
			send({'method': 'initialized', 'params': {}})
			send({'method': 'textDocument/didOpen', 'params': {'textDocument': {
				'uri': program.as_uri(), 'version': 1, 'languageId': 'astra', 'text': program.read_text()}}})
			send({'id': 2, 'method': 'textDocument/hover', 'params': {'textDocument': {'uri': program.as_uri()},
				'position': {'line': 4, 'character': program.read_text().splitlines()[4].index('compute') + 1}}})
			hover = receive(2)
			assert 'compute' in hover['result']['contents']['value'], hover
			send({'id': 3, 'method': 'shutdown', 'params': {}})
			assert receive(3)['result'] is None
			send({'method': 'exit', 'params': {}})
			process.stdin.close()
			assert process.wait(timeout=max(0.001, deadline - time.monotonic())) == 0
		finally:
			if process.poll() is None:
				os.killpg(process.pid, signal.SIGTERM)
				try:
					process.wait(timeout=3)
				except subprocess.TimeoutExpired:
					os.killpg(process.pid, signal.SIGKILL)
					process.wait(timeout=3)
			process.stdin.close()
			process.stdout.close()
			(consumer / 'lsp.stdout').write_bytes(wire)
	return {'command': command, 'exit': process.returncode, 'messages': responses,
		'stdout_sha256': sha(consumer / 'lsp.stdout'), 'stderr_sha256': sha(consumer / 'lsp.stderr')}


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--output', type=Path, required=True)
	parser.add_argument('--jobs', type=int, default=4)
	parser.add_argument('--liburing-prefix', type=Path)
	args = parser.parse_args()
	assert 1 <= args.jobs <= 16
	output = args.output.resolve()
	assert not output.is_relative_to(ROOT)
	assert subprocess.run(['git', 'diff', '--quiet', 'HEAD'], cwd=ROOT).returncode == 0, 'commit tracked task inputs first'
	output.mkdir(parents=True, exist_ok=True)
	work = Path(tempfile.mkdtemp(prefix='developer-build-', dir=output))
	head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
	epoch = int(subprocess.check_output(['git', 'show', '-s', '--format=%ct', 'HEAD'], cwd=ROOT, text=True))
	manifest = {'format': 'astra-developer-build/1', 'source_commit': head,
		'status': 'DEVELOPMENT_BUILD_NOT_RELEASE_CANDIDATE', 'checks': [], 'installations': []}
	def save():
		(work / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
	env = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	if args.liburing_prefix:
		pc = args.liburing_prefix.resolve() / 'lib/pkgconfig'
		assert (pc / 'liburing.pc').is_file()
		env['PKG_CONFIG_PATH'] = str(pc) + (os.pathsep + env['PKG_CONFIG_PATH'] if env.get('PKG_CONFIG_PATH') else '')
	def run(command, cwd=work):
		number = len(manifest['checks'])
		log = work / f'command-{number:03d}.log'
		with log.open('w') as stream:
			p = subprocess.run(list(map(str, command)), cwd=cwd, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=3600)
		manifest['checks'].append({'command': list(map(str, command)), 'cwd': str(cwd),
			'exit': p.returncode, 'log': log.name, 'log_sha256': sha(log)})
		save()
		assert p.returncode == 0, f'command failed: {log}'
		return log.read_text()
	run(['git', 'archive', '--format=tar', '-o', work / 'source.tar', head], ROOT)
	manifest['source_archive_sha256'] = sha(work / 'source.tar')
	for command in (['valac', '--version'], ['cc', '--version'], ['meson', '--version'], ['ninja', '--version'],
		['llvm-config', '--version'], ['pkg-config', '--modversion', 'glib-2.0', 'gobject-2.0']):
		run(command)
	for label in ('a', 'b'):
		source = work / ('source-' + label)
		source.mkdir()
		with tarfile.open(work / 'source.tar') as tar:
			tar.extractall(source, filter='data')
		build = work / ('build-' + label)
		stage = work / ('stage-' + label)
		maps = ['-ffile-prefix-map=' + str(source) + '=/usr/src/astra',
			'-ffile-prefix-map=' + str(build) + '=/usr/src/astra-build']
		run(['meson', 'setup', build, source, '--buildtype=release', '--prefix=/opt/astra', '--libdir=lib',
			'-Dwerror=true', '-Db_ndebug=false', '-Dhosted_concurrency=true', '-Dlinux_async=' + ('true' if args.liburing_prefix else 'false'),
			'-Dc_args=' + json.dumps(maps)])
		targets = json.loads((build / 'meson-info/intro-targets.json').read_text())
		selected = [t['name'] for t in targets if t.get('installed')]
		assert 'astrac' in selected
		run(['meson', 'compile', '-C', build, '-j', str(args.jobs), *selected])
		run(['meson', 'install', '-C', build, '--no-rebuild', '--destdir', stage])
		prefix = work / ('relocated-' + label)
		(stage / 'opt/astra').rename(prefix)
		# Make the source/build paths unavailable without deleting failed evidence.
		source.rename(work / ('preserved-source-' + label))
		build.rename(work / ('preserved-build-' + label))
		compiler = prefix / 'bin/astrac'
		version = run([compiler, '--version']).split()[1]
		run([compiler, '--policy-registry'])
		run([prefix / 'bin/astra-pkg', '--version'])
		run([prefix / 'bin/astra-lsp', '--version'])
		consumer = work / ('consumer-' + label)
		consumer.mkdir()
		program = consumer / 'main.astra'
		program.write_text('int compute(int input) {\n\tvar local = input + 2;\n\treturn local;\n}\nint main() { return compute(40) - 42; }\n')
		for level in ('0', '1', '2'):
			product = consumer / ('program-O' + level)
			run([compiler, '-O' + level, '-g', program, '-o', product], consumer)
			run([product], consumer)
			dynamic = run(['readelf', '-d', product])
			assert 'libglib' not in dynamic and 'libgobject' not in dynamic and 'libLLVM' not in dynamic
		formatted = run([compiler, '--format', program], consumer)
		assert formatted == program.read_text()
		run([compiler, '--format', '--check', program], consumer)
		run([compiler, '--check', program], consumer)
		package = consumer / 'package'
		run([prefix / 'bin/astra-pkg', 'create', package, '--name', 'installed-consumer',
			'--compiler-version', version, '--license', 'Apache-2.0 WITH LLVM-exception'], consumer)
		(package / 'library.astra').write_bytes(program.read_bytes())
		run([prefix / 'bin/astra-pkg', 'lock', '--package', package], consumer)
		run([prefix / 'bin/astra-pkg', 'build', '--package', package, '-O', '2', '-o', consumer / 'package-program'], consumer)
		run([consumer / 'package-program'], consumer)
		# A separate framed client executes the installed server with its default
		# colocated compiler; neither command names the source or original build.
		client = installed_lsp_client(prefix, program, consumer, env)
		manifest.setdefault('installed_lsp_clients', []).append({'label': label, **client})
		dependencies = run(['ldd', compiler])
		assert str(work) not in dependencies, 'installed compiler references a disposable build path'
		third_party = license_inventory(compiler, args.liburing_prefix)
		(prefix / 'share/licenses/astra/THIRD-PARTY.json').write_text(json.dumps(third_party, indent=2) + '\n')
		files = tree(prefix)
		assert 'share/licenses/astra/LICENSE.txt' in files
		assert 'share/astra/editor/extension.js' in files
		# A usable source library must include every supported checked-in unit
		# and explicit provider input, independently of its current compilation
		# option. Shipping a provider source does not implicitly select/link it.
		library_inputs = [path for path in (work / ('preserved-source-' + label) / 'lib/astra').rglob('*')
			if path.is_file() and path.suffix in ('.astra', '.vapi', '.c', '.h')]
		for path in library_inputs:
			relative = path.relative_to(work / ('preserved-source-' + label) / 'lib/astra')
			installed = 'share/astra/' + str(relative)
			assert installed in files and files[installed]['sha256'] == sha(path), f'missing/changed installed library input: {relative}'
		manifest['installations'].append({'label': label, 'compiler_sha256': sha(compiler), 'files': files})
		save()
	first, second = manifest['installations']
	manifest['differing_installed_paths'] = sorted(set(first['files']) | set(second['files']))
	manifest['differing_installed_paths'] = [p for p in manifest['differing_installed_paths'] if first['files'].get(p) != second['files'].get(p)]
	manifest['byte_reproducible'] = not manifest['differing_installed_paths']
	archive(work / 'relocated-a', work / 'astra-development-unqualified.tar.gz', epoch)
	manifest['binary_archive_sha256'] = sha(work / 'astra-development-unqualified.tar.gz')
	manifest['component_checks'] = {'independent_build_install_use': 'PASS',
		'reproducibility': 'PASS' if manifest['byte_reproducible'] else 'DIFFERENCES_REQUIRE_REVIEW'}
	save()
	print(work)
	print('Independent builds/relocated installations verified; byte-identical:', manifest['byte_reproducible'])
	print('Development artifacts only. This build does not grant release qualification.')


if __name__ == '__main__':
	main()
