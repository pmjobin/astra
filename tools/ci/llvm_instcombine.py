#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Rebuild one upstream translation unit for an isolated LLVM causal experiment."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shlex
import shutil
import subprocess
import tarfile

from common import ROOT, clean_environment, external, identify, require, run, sha, verify, write


def authenticate_headers(archive, llvm, runtime):
	"""Bind every build header and the producer to the authenticated binary archive."""
	process = subprocess.Popen(['zstd', '-d', '--long=31', '--stdout', str(archive)], stdout=subprocess.PIPE)
	seen, selected = set(), {}
	try:
		with tarfile.open(fileobj=process.stdout, mode='r|') as packed:
			for member in packed:
				name = member.name.rstrip('/')
				path = PurePosixPath(name)
				require(name and not path.is_absolute() and '..' not in path.parts and '\\' not in name and name == str(path) and name not in seen, 'unsafe or duplicate upstream member')
				seen.add(name)
				prefix = 'LLVM-23.1.4-Linux-X64/'
				key = name.removeprefix(prefix)
				if not name.startswith(prefix) or not member.isfile() or not (key.startswith('include/') or (key.startswith('lib/clang/') and '/include/' in key) or key == 'bin/clang-23'):
					continue
				data = packed.extractfile(member).read()
				pin = dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
				verify(llvm/key, pin)
				selected[key] = pin
		require(process.wait() == 0 and 'bin/clang-23' in selected and len(selected) > 100, 'incomplete header/producer authentication')
	finally:
		process.stdout.close()
		if process.poll() is None:
			process.kill()
			process.wait()
	write(runtime/'headers.json', selected)
	return selected


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('archive', 'source', 'llvm', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--producer', choices=('clang', 'gcc'), default='clang')
	a = p.parse_args()
	lock = json.loads((ROOT/'tools/ci/llvm-linux.json').read_text())
	source_lock = json.loads((ROOT/'tools/release/licenses/llvm-23.1.4/third-party/SOURCE.json').read_text())
	verify(a.archive, lock['archive'])
	verify(a.source, source_lock['source_archive'])
	for name, pin in lock['files'].items():
		verify(a.llvm/name, pin)
	build, runtime = external(a.build), external(a.runtime)
	recipe = Path(__file__).read_bytes()
	(runtime/'executed-recipe.py.txt').write_bytes(recipe)
	headers = authenticate_headers(a.archive, a.llvm, runtime)
	source = build/'llvm-source'
	source.mkdir()
	with tarfile.open(a.source) as packed:
		for member in packed:
			prefix = 'llvm-project-23.1.4.src/llvm/lib/Transforms/InstCombine/'
			if not member.name.startswith(prefix) or not member.isfile():
				continue
			path = source/member.name.removeprefix(prefix)
			require(path.parent == source and not path.exists(), 'unexpected InstCombine source member')
			path.write_bytes(packed.extractfile(member).read())
	unit = source/'InstructionCombining.cpp'
	require(sha(unit) == '9df7af07a0cf705ad952e6364103103157e46870253e33bad437e38295da076e', 'unexpected upstream translation unit')
	env = clean_environment()
	config = a.llvm/'bin/llvm-config'
	require(subprocess.check_output([config, '--version'], env=env).strip() == b'23.1.4', 'wrong LLVM version')
	system_cxx = Path(shutil.which('g++', path='/usr/bin:/bin')).resolve()
	compiler = a.llvm/'bin/clang-23' if a.producer == 'clang' else system_cxx
	flags = shlex.split(subprocess.check_output([config, '--cxxflags'], env=env, text=True))
	obj = build/'InstructionCombining.cpp.o'
	run([compiler, *flags, '-O3', '-g1', '-DNDEBUG', '-fPIC', '-c', unit, '-o', obj], runtime/'compile', env, timeout=600)
	archive = build/'libLLVMInstCombine.a'
	shutil.copyfile(a.llvm/'lib/libLLVMInstCombine.a', archive)
	run(['ar', 'r', archive, obj], runtime/'replace-member', env)
	libraries = shlex.split(subprocess.check_output([config, '--libfiles'], env=env, text=True))
	require(all(Path(name).resolve().is_relative_to(a.llvm.resolve()/'lib') and str(Path(name).relative_to(a.llvm)) in lock['files'] for name in libraries), 'untrusted link input')
	require(sum(Path(name).name == 'libLLVMInstCombine.a' for name in libraries) == 1, 'ambiguous InstCombine archive')
	selected = [str(archive) if Path(name).name == 'libLLVMInstCombine.a' else name for name in libraries]
	system = shlex.split(subprocess.check_output([config, '--system-libs'], env=env, text=True))
	system = ['-lzstd' if name.endswith('/libzstd.a') else name for name in system]
	require(set(system) <= {'-lrt', '-ldl', '-lm', '-lz', '-lzstd', '-lxml2'}, 'unexpected system dependency')
	library = build/'libLLVM.so.23.1'
	linker = system_cxx
	run([linker, '-shared', '-Wl,-soname,libLLVM.so.23.1', '-Wl,--whole-archive', *selected, '-Wl,--no-whole-archive', *system, '-o', library], runtime/'link', env, timeout=600)
	dependencies, _ = run(['ldd', library], runtime/'dependencies', env)
	require(b'not found' not in dependencies, 'diagnostic library dependency missing')
	require(sha(__file__) == hashlib.sha256(recipe).hexdigest(), 'recipe changed during execution')
	write(runtime/'result.json', dict(status='LLVM_INSTCOMBINE_DIAGNOSTIC_DERIVATIVE', dependency_label='LLVM 23.1.4 + unmodified InstCombine translation unit rebuild', source_patch=None, public_distribution_approved=False, archive=identify(a.archive), source_archive=identify(a.source), sources={path.name:sha(path) for path in source.iterdir()}, headers_sha256=sha(runtime/'headers.json'), header_count=len(headers), producer=identify(compiler), linker=identify(linker), object=identify(obj), replacement_archive=identify(archive), original_archives={name:sha(name) for name in libraries}, library=identify(library), recipe_sha256=sha(__file__), scope='Causal experiment only. Existing bootstrap and package validators deliberately reject this receipt; no approved dependency substitution or safety qualification is implied.'))
	print(library)


if __name__ == '__main__':
	main()
