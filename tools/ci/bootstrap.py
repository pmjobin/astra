#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build paired native/doc compilers from authenticated seed and frozen Git source."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shlex
import shutil
import subprocess

from common import ROOT, clean_environment, external, identify, require, run, sha, verify, write
from trust import fetch, host, seed_manifest

LIBRARIES = ['base/errors', 'base/diagnostics', 'text/utf8-message', 'text/utf8-byte-builder', 'text/scalar-format', 'hosted/text-ops', 'collections/bag', 'collections/vector', 'hosted/files', 'hosted/text']
PROVIDERS = ['lib/runtime/platform/'+n+'.c' for n in ('args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap')]+['compiler/backend/llvm/capi.c', 'compiler/driver/arguments.c']


def git(*args):
	return subprocess.check_output(['git', '-C', str(ROOT), *args], text=True).strip()


def authenticate_llvm(root, lock):
	require(lock['format'] == 'astra-toolchain/1' and lock['version'] == '23.1.4', 'wrong LLVM identity')
	host(lock)
	require(lock['files'], 'LLVM extracted identities have not been pinned')
	for name, pin in lock['files'].items():
		verify(root/name, pin)
	config = root/lock['config']
	env = clean_environment()
	env['LD_LIBRARY_PATH'] = str(root/'lib')
	require(subprocess.check_output([config, '--version'], env=env).strip() == b'23.1.4', 'LLVM version mismatch')
	return config, env


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('seed', 'llvm', 'library', 'library_receipt', 'build', 'runtime'):
		p.add_argument('--'+key.replace('_', '-'), type=Path, required=key != 'seed')
	p.add_argument('--seed-manifest', type=Path, default=Path(__file__).with_name('seed-linux.json'))
	p.add_argument('--llvm-manifest', type=Path, default=Path(__file__).with_name('llvm-linux.json'))
	p.add_argument('--commit', required=True)
	p.add_argument('--stages', type=int, choices=(1, 2, 3), default=2)
	p.add_argument('--jobs', type=int, choices=(1, 2), default=2)
	p.add_argument('--timeout', type=int, default=7200)
	a = p.parse_args()
	require(re.fullmatch('[0-9a-f]{40}', a.commit) and git('rev-parse', 'HEAD') == a.commit, 'checkout identity mismatch')
	require(not git('diff', 'HEAD', '--', 'compiler', 'lib', 'tools/ci'), 'commit build inputs first')
	seed_lock = seed_manifest(a.seed_manifest)
	llvm_lock = json.loads(a.llvm_manifest.read_text())
	config, env = authenticate_llvm(a.llvm.resolve(), llvm_lock)
	library_receipt = json.loads(a.library_receipt.read_text())
	require(library_receipt['status'] == 'LLVM_DYLIB_BUILT_NOT_QUALIFIED' and library_receipt['archive_sha256'] == llvm_lock['archive']['sha256'], 'LLVM library provenance mismatch')
	require(all(llvm_lock['files']['lib/'+Path(name).name]['sha256'] == digest for name, digest in library_receipt['inputs'].items()), 'LLVM link inputs differ from pinned archive')
	library = verify(a.library, library_receipt['library']).resolve()
	env['LD_LIBRARY_PATH'] = str(library.parent)
	build, runtime = external(a.build), external(a.runtime)
	seed = verify(a.seed, seed_lock) if a.seed else fetch(seed_lock, build/'seed')
	seed.chmod(seed.stat().st_mode | 0o100) if a.seed is None else None
	require(seed.read_bytes()[:5] == b'\x7fELF\x02', 'seed is not ELF64')
	require(shutil.disk_usage(build).free >= 4*1024**3, 'insufficient free build storage')
	compiler = [n for n in git('ls-tree', '-r', '--name-only', a.commit, 'compiler').splitlines() if n.endswith('.astra')]
	inputs = [ROOT/n for n in compiler]+[ROOT/'lib/astra'/Path(n+'.astra') for n in LIBRARIES]
	all_sources = inputs+[ROOT/n for n in PROVIDERS]+[ROOT/'compiler/docs/host.c', ROOT/'compiler/driver/doc-guard.c', ROOT/'compiler/driver/doc-launch.c']
	identities = {str(n.relative_to(ROOT)):identify(n) for n in all_sources}
	for name, row in identities.items():
		require(subprocess.check_output(['git', '-C', ROOT, 'show', a.commit+':'+name]) == Path(row['path']).read_bytes(), 'uncommitted source: '+name)
	cc = Path(shutil.which('cc', path='/usr/bin:/bin')).resolve()
	env['PATH'] = str(a.llvm.resolve()/'bin')+':/usr/bin:/bin'
	material = dict(format='astra-bootstrap-source/1', source_commit=a.commit, source_tree=git('rev-parse', a.commit+'^{tree}'), sources=identities, seed=seed_lock, llvm=llvm_lock, library=identify(library), library_receipt_sha256=sha(a.library_receipt), cc=identify(cc), recipe_sha256=sha(__file__), source_path_convention='identical repository-relative input names, cwd at the authenticated checkout; source origin strings contain no developer home path')
	write(runtime/'identity.json', material)
	(runtime/'executed-bootstrap.py.txt').write_bytes(Path(__file__).read_bytes())
	fingerprint = hashlib.sha256(json.dumps(material, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
	write(runtime/'docs-build-identity.json', dict(fingerprint=fingerprint, material=material))
	provider_dir = build/'providers'
	provider_dir.mkdir()
	objects = []
	for name in PROVIDERS+['compiler/docs/host.c', 'compiler/driver/doc-guard.c']:
		obj = provider_dir/('llvm-capi.o' if name.endswith('/capi.c') else Path(name).stem+'.o')
		extra = shlex.split(subprocess.check_output([config, '--cflags'], text=True, env=env)) if name.endswith('/capi.c') else []
		if name.endswith('/host.c'):
			extra.append('-DASTRA_DOC_BUILD_SHA256="'+fingerprint+'"')
		if name.endswith('/doc-guard.c'):
			# Ubuntu warns for the guard's deliberate best-effort stderr write.
			# The source still unconditionally _Exit(127); no verifier is disabled.
			extra.append('-Wno-error=unused-result')
		run([cc, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *extra, '-c', ROOT/name, '-o', obj], runtime/('provider-'+Path(name).stem), env)
		if not name.endswith('/doc-guard.c'):
			objects.append(obj)
	write(runtime/'link.json', dict(objects={str(obj):sha(obj) for obj in objects if obj.name != 'host.o'}))
	tool_paths = [config, library, cc, a.llvm.resolve()/'bin/opt']
	write(runtime/'toolchain.json', dict(tools={str(path):sha(path) for path in tool_paths}, environment={key:env.get(key) for key in ('PATH', 'LD_LIBRARY_PATH', 'LIBRARY_PATH', 'LC_ALL')}))
	run([seed, '--help'], runtime/'seed-help', env)
	previous = seed
	stages = []
	for stage in range(1, a.stages+1):
		stage_build, stage_runtime = build/('stage'+str(stage)), runtime/('stage'+str(stage))
		stage_build.mkdir()
		stage_runtime.mkdir()
		producer = identify(previous)
		def profile(mode):
			leaf = stage_runtime/mode
			obj = stage_build/('astrac-'+mode+'.o')
			exe = stage_build/('astrac-'+mode)
			run([previous, '-c', '-'+mode, '-o', obj, *[n.relative_to(ROOT) for n in inputs]], leaf/'compile', env, timeout=a.timeout, cwd=ROOT)
			native, doc = Path(str(exe)+'.native'), Path(str(exe)+'.doc')
			common = [cc, '-no-pie', obj, *objects]
			run([*common, library, '-Wl,-rpath,$ORIGIN/llvm', '-o', native], leaf/'native-link', env)
			undefined, _ = run(['nm', '-u', native], leaf/'imports', env)
			names = sorted(set(re.findall(rb'\b(LLVM[A-Za-z0-9_]+)(?:@[^\s]+)?\s*$', undefined, re.M)))
			require(b'LLVMContextCreate' in names and b'LLVMShutdown' in names, 'LLVM import boundary missing')
			run([*common, provider_dir/'doc-guard.o', *['-Wl,--defsym='+n.decode()+'=astrac_doc_backend_unavailable' for n in names], '-o', doc], leaf/'doc-link', env)
			run([cc, '-std=c11', '-'+mode, '-Wall', '-Wextra', '-Werror', ROOT/'compiler/driver/doc-launch.c', '-o', exe], leaf/'launcher', env)
			dependencies, _ = run(['ldd', doc], leaf/'doc-dependencies', env)
			require(b'LLVM' not in dependencies, 'doc image links LLVM')
			out, err = run([exe, '--version'], leaf/'version', env)
			require(out == b'astrac 0.0.3-dev28c1 (GNU/Linux x86-64, E25-A-v1, LLVM 23.1.4)\n' and not err, 'unexpected compiler version')
			run(['readelf', '-h', '-d', native], leaf/'elf', env)
			product = dict(status='BUILT_NOT_QUALIFIED', **identify(exe), object=str(obj), object_sha256=sha(obj), native=identify(native), doc=identify(doc))
			write(leaf/'product.json', product)
			print('Stage', stage, mode, 'built', product['native']['sha256'], flush=True)
			return mode, product
		with ThreadPoolExecutor(max_workers=a.jobs) as pool:
			products = dict(pool.map(profile, ('O0', 'O2')))
		for row in identities.values():
			verify(row['path'], row)
		verify(previous, producer)
		result = dict(stage=stage, producer=producer, products=products, identity_sha256=sha(runtime/'identity.json'))
		write(stage_runtime/'result.json', result)
		stages.append(result)
		previous = Path(products['O2']['path'])
	comparisons = []
	for left, right in zip(stages, stages[1:]):
		for mode in ('O0', 'O2'):
			for kind in ('object_sha256', 'sha256', 'native', 'doc'):
				x, y = left['products'][mode][kind], right['products'][mode][kind]
				comparisons.append(dict(stages=[left['stage'], right['stage']], profile=mode, kind=kind, equal=x['sha256'] == y['sha256'] if isinstance(x, dict) else x == y))
	write(runtime/'result.json', dict(status='BUILT_REQUIRES_NATIVE_QUALIFICATION', stages=stages, comparisons=comparisons, products=stages[-1]['products'], identity_sha256=sha(runtime/'identity.json'), reproducible=bool(comparisons) and all(row['equal'] for row in comparisons)))
	require(all(row['equal'] for row in comparisons), 'generation products differ; retain evidence and investigate')


if __name__ == '__main__':
	main()
