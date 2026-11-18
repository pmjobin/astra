#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Distribution-owned Linux LLVM contract; private bootstrap is a separate input."""
import ctypes
import json
from pathlib import Path
import platform
import re
import subprocess

from common import identify, require, run


def rhel9(os_release):
	return os_release['ID'].strip('"') == 'rhel' and os_release['VERSION_ID'].strip('"').split('.')[0] == '9'


def discover(kind, runtime, env):
	os_release = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
	distro, release = os_release['ID'].strip('"'), os_release['VERSION_ID'].strip('"')
	require(platform.machine() == 'x86_64', 'wrong system LLVM architecture')
	if kind == 'deb':
		require((distro, release) == ('ubuntu', '26.04'), 'wrong system LLVM target')
		major, config, development, consumer = 22, '/usr/bin/llvm-config-22', 'llvm-22-dev', 'libllvm22'
	else:
		el9 = distro in ('centos', 'rhel') and release.split('.')[0] == '9'
		require(kind == 'rpm' and ((distro, release) == ('fedora', '45') or el9), 'wrong system LLVM target')
		major, config, development, consumer = 22 if rhel9(os_release) else 23, '/usr/bin/llvm-config', 'llvm-devel', 'llvm-libs'
	def query(*args):
		return subprocess.check_output([config, *args], env=env, text=True).strip()
	version = query('--version')
	require(int(version.split('.')[0]) == major, 'wrong system LLVM major')
	if major == 23:
		require(re.fullmatch(r'23\.1\.\d+', version), 'system LLVM 23.1.x required')
	if rhel9(os_release):
		require(version == '22.1.8', 'RHEL 9 requires the qualified system LLVM 22.1.8')
	files = query('--link-shared', '--libfiles').split()
	require(len(files) == 1, 'system LLVM must be one shared library')
	library = Path(files[0]).resolve(strict=True)
	include = Path(query('--includedir')).resolve(strict=True)
	require(library.is_relative_to('/usr/lib') or library.is_relative_to('/usr/lib64'), 'private LLVM library path')
	require(include.is_relative_to('/usr/include') or include.is_relative_to('/usr/lib') or include.is_relative_to('/usr/lib64'), 'private LLVM header path')
	owner_args = ['dpkg-query', '-S', str(library)] if kind == 'deb' else ['rpm', '-qf', '--qf', '%{NAME}\n', library]
	owner, _ = run(owner_args, runtime/'system-library-owner', env)
	require((consumer+':').encode() in owner or (consumer+':amd64:').encode() in owner or owner.strip() == consumer.encode(), 'LLVM library is not distribution-owned')
	header = (include/'llvm-c/Core.h').resolve(strict=True)
	owner, _ = run(['dpkg-query', '-S', str(header)] if kind == 'deb' else ['rpm', '-qf', '--qf', '%{NAME}\n', header], runtime/'system-header-owner', env)
	require(development.encode() in owner, 'LLVM headers are not distribution-owned')
	run(['dpkg-query', '-W', development, consumer] if kind == 'deb' else ['rpm', '-qi', development, consumer], runtime/'system-packages', env)
	run(['apt-cache', 'policy', development, consumer] if kind == 'deb' else ['dnf', 'info', '--installed', development, consumer], runtime/'system-repository', env)
	elf, _ = run(['readelf', '-d', library], runtime/'system-library-elf', env)
	sonames = re.findall(rb'\(SONAME\).*?\[(.*?)\]', elf)
	require(len(sonames) == 1, 'missing system LLVM SONAME')
	if major == 23:
		require(sonames[0] == b'libLLVM.so.23.1', 'wrong system LLVM SONAME')
	if rhel9(os_release):
		require(sonames[0] == b'libLLVM.so.22.1', 'wrong RHEL 9 system LLVM SONAME')
		verification, _ = run(['rpm', '-V', development, consumer], runtime/'system-package-integrity', env)
		require(not verification.strip(), 'modified RHEL 9 LLVM package')
	loaded = ctypes.CDLL(str(library))
	loaded.LLVMGetVersion.argtypes = [ctypes.POINTER(ctypes.c_uint)]*3
	fields = [ctypes.c_uint() for unused in range(3)]
	loaded.LLVMGetVersion(*map(ctypes.byref, fields))
	require([field.value for field in fields] == list(map(int, version.split('.'))), 'LLVM header/runtime version mismatch')
	return dict(policy='SYSTEM_LLVM', major=major, version=version, config=config, include=str(include), library=identify(library), soname=sonames[0].decode(), development_package=development, runtime_package=consumer, os_release=os_release)


def audit_payload(stage):
	for path in stage.rglob('*'):
		rel = path.relative_to(stage)
		require(not path.is_symlink(), 'Linux payload symlink refused: '+str(rel))
		require(not any(part.lower().startswith('libllvm') for part in rel.parts), 'bundled LLVM payload refused: '+str(rel))
		require(not str(rel).startswith(('usr/include/llvm', 'usr/lib/astra/llvm')), 'LLVM runtime or headers refused')
		if path.is_file():
			with path.open('rb') as stream:
				magic = stream.read(8)
			require(not magic.startswith(b'!<arch>'), 'private static archive refused')
			if magic.startswith(b'\x7fELF'):
				require(str(rel) in ('usr/lib/astra/astrac', 'usr/lib/astra/astrac.native', 'usr/lib/astra/astrac.doc'), 'undocumented binary payload refused: '+str(rel))
			require(path.suffix not in ('.so', '.a') and not path.name.endswith(('.h', '.hpp')) or not any(part.lower().startswith('llvm') for part in rel.parts), 'LLVM provider payload refused')


def audit_elf(native, llvm, runtime, env):
	elf, _ = run(['readelf', '-h', '-d', native], runtime/'system-native-elf', env)
	require(b'Advanced Micro Devices X86-64' in elf and b'ELF64' in elf, 'wrong compiler architecture')
	require(b'(RPATH)' not in elf and b'(RUNPATH)' not in elf, 'private loader search path refused')
	needed = re.findall(rb'\(NEEDED\).*?\[(.*?)\]', elf)
	require([name.decode() for name in needed if b'LLVM' in name] == [llvm['soname']], 'wrong LLVM dependency')
	deps, _ = run(['ldd', native], runtime/'system-loader', env)
	require(b'not found' not in deps, 'missing system dependency')
	paths = re.findall(rb'libLLVM[^\s]*\s+=>\s+(\S+)', deps)
	require(len(paths) == 1 and Path(paths[0].decode()).resolve() == Path(llvm['library']['path']), 'wrong LLVM loader resolution')
	if rhel9(llvm['os_release']):
		versions, _ = run(['readelf', '-l', '-V', native], runtime/'rhel9-native-versions', env)
		require(b'[Requesting program interpreter: /lib64/ld-linux-x86-64.so.2]' in versions, 'wrong RHEL 9 interpreter')
		glibc = [tuple(map(int, number.split(b'.'))) for number in re.findall(rb'\bGLIBC_(\d+(?:\.\d+)+)\b', versions)]
		require(glibc and max(glibc) <= (2, 34), 'native program requires glibc newer than RHEL 9')
		symbols, _ = run(['nm', '-D', '--undefined-only', native], runtime/'rhel9-native-imports', env)
		imports = re.findall(rb'\bLLVM[A-Za-z0-9_]+(?:@[^\s]+)?$', symbols, re.M)
		require(imports and all(name.endswith(b'@LLVM_22.1') for name in imports), 'wrong RHEL 9 versioned LLVM imports')
	return [name.decode() for name in needed]
