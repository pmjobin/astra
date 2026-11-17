#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Link official LLVM 23.1.4 static archives into a distro-native C API library."""
import argparse
import json
from pathlib import Path
import shlex
import shutil
import subprocess

from common import clean_environment, external, identify, require, run, sha, verify, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for key in ('llvm', 'manifest', 'build', 'runtime'):
		p.add_argument('--'+key, type=Path, required=True)
	a = p.parse_args()
	lock = json.loads(a.manifest.read_text())
	require(lock['version'] == '23.1.4' and lock['archive']['sha256'] == 'efdd1dbd089b99bfcfcde7b8eb1236163f2e88df5a981cca4f783ec9cb5e0378', 'unreviewed LLVM source archive')
	require(lock['files'], 'LLVM member pins missing')
	for name, pin in lock['files'].items():
		verify(a.llvm/name, pin)
	build, runtime = external(a.build), external(a.runtime)
	config = a.llvm/'bin/llvm-config'
	env = clean_environment()
	require(subprocess.check_output([config, '--version'], env=env).strip() == b'23.1.4', 'wrong LLVM version')
	libraries = [str(Path(n).resolve()) for n in shlex.split(subprocess.check_output([config, '--libfiles'], env=env, text=True))]
	require(all(Path(n).resolve().is_relative_to(a.llvm.resolve()/'lib') for n in libraries), 'LLVM archives escape root')
	require(all(str(Path(n).relative_to(a.llvm)) in lock['files'] for n in libraries), 'untrusted LLVM link input')
	system = shlex.split(subprocess.check_output([config, '--system-libs'], env=env, text=True))
	# Upstream records its build host's zstd archive path; resolve the declared
	# zstd dependency through this distro's native linker instead.
	system = ['-lzstd' if n.endswith('/libzstd.a') else n for n in system]
	require(set(system) <= {'-lrt', '-ldl', '-lm', '-lz', '-lzstd', '-lxml2'}, 'unexpected LLVM system dependency')
	cxx = Path(shutil.which('g++', path='/usr/bin:/bin')).resolve()
	out = build/'libLLVM.so.23.1'
	run([cxx, '-shared', '-Wl,-soname,libLLVM.so.23.1', '-Wl,--whole-archive', *libraries, '-Wl,--no-whole-archive', *system, '-o', out], runtime/'link', env, timeout=600)
	run(['strip', '--strip-debug', out], runtime/'strip-debug', env)
	deps, _ = run(['ldd', out], runtime/'dependencies', env)
	require(b'not found' not in deps, 'LLVM runtime dependency missing')
	run(['readelf', '-d', '--version-info', out], runtime/'elf', env)
	write(runtime/'result.json', dict(status='LLVM_DYLIB_BUILT_NOT_QUALIFIED', upstream_manifest_sha256=sha(a.manifest), archive_sha256=lock['archive']['sha256'], inputs={str(n):sha(n) for n in libraries}, cxx=identify(cxx), os_release=Path('/etc/os-release').read_text(), library=identify(out)))
	print(out)


if __name__ == '__main__':
	main()
