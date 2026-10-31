# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build the Astra indexer from its own libraries or opaque native units."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import tempfile
import time


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
LIBRARIES = ['base/errors.astra', 'collections/box.astra', 'collections/bag.astra',
	'collections/map.astra', 'collections/cache.astra', 'text/utf8-message.astra',
	'text/utf8-byte-builder.astra', 'hosted/files.astra', 'hosted/text-ops.astra',
	'text/scalar-format.astra', 'hosted/text.astra']
ADAPTERS = ['args-posix', 'text-posix', 'text-ops-posix', 'files-posix']
FOUNDATION = ['Receipt', 'SinkFailure', 'SinkState<int>', 'Store', 'Document',
	'Summary', 'Word', 'SourceText', 'SourceEnvelope', 'IdentifierPolicy', 'Error',
	'IndexError', 'FileError', 'InvalidUtf8', 'TextCapacityError', 'TextRangeError',
	'Utf8Message', 'Utf8ByteBuilder', 'FileBytes', 'Box<int>',
	'Box<IndexFoundation.Summary>', 'Box<IndexFoundation.FileBytes>',
	'Box<IndexFoundation.SourceEnvelope>', 'MapEntry<int,IndexFoundation.Document>',
	'Map<int,IndexFoundation.Document>', 'Cache<int,IndexFoundation.Document>',
	'Map<int,IndexFoundation.Document>::lookup<IndexFoundation.Summary>',
	'Map<int,IndexFoundation.Document>::inspect<IndexFoundation.Summary>',
	'Map<int,IndexFoundation.Document>::lookup_with<int,int>',
	'Map<int,IndexFoundation.Document>::inspect_with<int,int>',
	'Cache<int,IndexFoundation.Document>::lookup<IndexFoundation.Summary>',
	'Cache<int,IndexFoundation.Document>::lookup_with<int,int>',
	'MapEntry<int,IndexFoundation.Box<int>>', 'Map<int,IndexFoundation.Box<int>>',
	'Map<int,IndexFoundation.Box<int>>::lookup<int>',
	'Map<int,IndexFoundation.Box<int>>::inspect<int>', 'read_file', 'require_text',
	'text_byte', 'append_text', 'append_int', 'write_byte', 'print', 'println_stderr']
ANALYSIS = ['AsciiPolicy', 'analyze', 'process', 'prepare_report', 'append_path',
	'append_byte', 'append_number']


def sha(path):
	return hashlib.sha256(path.read_bytes()).hexdigest()


def build(compiler, output, library_root, mode, levels, async_profile=None, runtime_root=None, uring_prefix=None, async_entry="batch", read_fault=False):
	compiler = compiler.resolve(strict=True)
	library_root = library_root.resolve(strict=True)
	output = output.resolve()
	assert not output.is_relative_to(ROOT), 'generated outputs must remain outside the repository'
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix=mode + '-indexer-', dir=output))
	sources = [HERE / name for name in ['foundation.astra', 'analysis.astra',
		('async-batch-cli.astra' if async_entry == 'batch' else 'async-cli.astra') if async_profile else 'cli.astra']]
	extras = [HERE / name for name in ['async-foundation.astra', 'async-analysis.astra', 'async-observer.c']] if async_profile else []
	if async_profile and async_entry == 'batch':
		extras += [HERE / 'async-batch-foundation.astra', HERE / 'async-batch-analysis.astra']
	libraries = [library_root / name for name in LIBRARIES]
	adapters = [library_root / ('platform/' + name + '.c') for name in ADAPTERS]
	if async_profile:
		adapters.append(HERE / 'async-observer.c')
	if read_fault:
		adapters.append(HERE / 'read-fault.c')
	headers = [path.with_suffix('.h') for path in adapters if path.with_suffix('.h').is_file()]
	runtimes = []
	if async_profile:
		if runtime_root is None:
			runtime_root = compiler.parent / 'lib/astra'
			if not runtime_root.is_dir():
				runtime_root = compiler.parent.parent / 'lib/astra'
		runtimes.append(runtime_root.resolve(strict=True) / 'async-virtual.o')
		if async_profile == 'linux':
			assert uring_prefix is not None, '--uring-prefix is required for the Linux profile'
			runtimes += [runtime_root / 'libastra-async-linux.a', uring_prefix.resolve(strict=True) / 'lib/liburing.a']
	receipt = dict(format='astra-m15-indexer-build/1', mode=mode, levels=levels, async_profile=async_profile, async_entry=async_entry if async_profile else None, read_fault=read_fault,
		compiler=str(compiler), compiler_sha256=sha(compiler),
		sources={str(p): sha(p) for p in [Path(__file__), *sources, *extras, *libraries, *adapters, *headers]},
		runtimes={str(p): sha(p) for p in runtimes}, checks=[], products={}, producer_sources_hidden=False,
		scope='Build evidence only; application behavior and milestone gates require separate qualification.')

	def save():
		(out / 'build.json').write_text(json.dumps(receipt, indent='\t') + '\n')

	def run(argv):
		argv = list(map(str, argv))
		started = time.perf_counter()
		result = subprocess.run(argv, cwd=out, capture_output=True, timeout=120,
			env=dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1'))
		passed = result.returncode == 0 and not result.stdout and not result.stderr
		receipt['checks'].append(dict(argv=argv, exit=result.returncode,
			elapsed_seconds=time.perf_counter() - started, stdout=result.stdout.decode(errors='replace'),
			stderr=result.stderr.decode(errors='replace'), passed=passed))
		save()
		assert passed, receipt['checks'][-1]

	foundation = out / 'foundation-implementation.astra'
	foundation.write_bytes(b'\n'.join(path.read_bytes() for path in [sources[0], *libraries]))
	analysis = out / 'analysis-implementation.astra'
	analysis.write_bytes(sources[1].read_bytes())
	client = out / 'cli.astra'
	client.write_bytes(sources[2].read_bytes())
	foundation_extra = []
	analysis_extra = []
	if async_profile:
		parts = [(0, foundation_extra), (1, analysis_extra)]
		if async_entry == 'batch':
			parts += [(3, foundation_extra), (4, analysis_extra)]
		for index, destination in parts:
			copy = out / extras[index].name
			text = extras[index].read_text()
			if async_profile == 'linux' and destination is analysis_extra:
				text = text.replace('VirtualExecutor', 'LinuxExecutor').replace('returns AsyncStatus;',
					'returns AsyncStatus provider "linux-io-uring";').replace('delay_ticks(3)', 'delay_ms(100)')
			copy.write_text(text)
			destination.append(copy)
		if async_profile == 'linux':
			text = client.read_text().replace('VirtualExecutor', 'LinuxExecutor').replace('returns RunStatus;',
				'returns RunStatus provider "linux-io-uring";').replace('executor.advance(2);', '').replace('executor.advance(1);', 'executor.wait();')
			client.write_text(text)

	objects = list(runtimes)
	for source in adapters:
		obj = out / (source.stem + '.o')
		run(['cc', '-std=c11', '-g', '-O2', '-Wall', '-Wextra', '-Werror',
			*(['-Dastra_file_read_buffer=astra_real_file_read_buffer'] if read_fault and source.stem == 'files-posix' else []),
			'-c', source, '-o', obj])
		objects.append(obj)
	if mode == 'native':
		foundation_exports = FOUNDATION + (['AsyncError', 'ClassificationTable', 'async_watch'] if async_profile else [])
		if async_profile and async_entry == 'batch':
			foundation_exports += ['BatchArgument', 'BatchInput', 'BatchSummary']
		analysis_exports = ANALYSIS + (['process_async'] if async_profile else [])
		if async_profile and async_entry == 'batch':
			analysis_exports += ['process_batch']
		for module, implementation, extra, exported, level, imports in [
			('IndexFoundation', foundation, foundation_extra, foundation_exports, levels[0], []),
			('IndexAnalysis', analysis, analysis_extra, analysis_exports, levels[1], [out / 'foundation.asti'])]:
			stem = 'foundation' if module == 'IndexFoundation' else 'analysis'
			run([compiler, '-g', '-O' + str(level), '-c', '--module', module,
				*[arg for name in exported for arg in ['--native-export', module + '.' + name]],
				*[arg for path in imports for arg in ['--import-module', path]],
				'--emit-interface', out / (stem + '.asti'), implementation, *extra, '-o', out / (stem + '.o')])
			implementation.unlink()
			for copy in extra:
				copy.unlink()
			receipt['products'][str(out / (stem + '.asti'))] = sha(out / (stem + '.asti'))
			receipt['products'][str(out / (stem + '.o'))] = sha(out / (stem + '.o'))
		assert not any(path.exists() for path in [foundation, analysis, *foundation_extra, *analysis_extra])
		receipt['producer_sources_hidden'] = True
		run([compiler, '-g', '-O' + str(levels[2]), '--import-module', out / 'analysis.asti',
			client, *[arg for obj in objects for arg in ['--link-object', obj]], '-o', out / 'indexer'])
	else:
		run([compiler, '-g', '-O' + str(levels[2]), '--entry-object', foundation, *foundation_extra, analysis, *analysis_extra, client,
			'-o', out / 'indexer.o'])
		run(['cc', '-no-pie', out / 'indexer.o', *objects, '-o', out / 'indexer'])
		receipt['products'][str(out / 'indexer.o')] = sha(out / 'indexer.o')
	assert sha(compiler) == receipt['compiler_sha256'], 'compiler changed during build'
	assert all(sha(Path(path)) == digest for path, digest in receipt['runtimes'].items()), 'runtime changed during build'
	assert all(sha(Path(path)) == digest for path, digest in receipt['sources'].items()), 'source changed during build'
	for obj in objects:
		receipt['products'][str(obj)] = sha(obj)
	receipt['products'][str(out / 'indexer')] = sha(out / 'indexer')
	receipt['built'] = True
	save()
	return out / 'build.json'


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('compiler', type=Path)
	parser.add_argument('output', type=Path)
	parser.add_argument('--library-root', type=Path, default=ROOT / 'lib/astra')
	parser.add_argument('--mode', choices=['native', 'mono'], default='native')
	parser.add_argument('--levels', nargs=3, type=int, choices=[0, 1, 2], default=[0, 0, 0],
		help='Foundation, Analysis and CLI public optimization levels')
	parser.add_argument('--async-profile', choices=['virtual', 'linux'])
	parser.add_argument('--async-entry', choices=['batch', 'single'], default='batch')
	parser.add_argument('--read-fault-adapter', action='store_true')
	parser.add_argument('--runtime-root', type=Path)
	parser.add_argument('--uring-prefix', type=Path)
	args = parser.parse_args()
	print(build(args.compiler, args.output, args.library_root, args.mode, args.levels,
		args.async_profile, args.runtime_root, args.uring_prefix, args.async_entry, args.read_fault_adapter))


if __name__ == '__main__':
	main()
