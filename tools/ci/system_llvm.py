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


def discover(kind, runtime, env):
	os_release = dict(line.split('=', 1) for line in Path('/etc/os-release').read_text().splitlines() if '=' in line)
	distro, release, major, config, development, consumer = ('ubuntu', '26.04', 22, '/usr/bin/llvm-config-22', 'llvm-22-dev', 'libllvm22') if kind == 'deb' else ('fedora', '45', 23, '/usr/bin/llvm-config', 'llvm-devel', 'llvm-libs')
	require(os_release['ID'].strip('"') == distro and os_release['VERSION_ID'].strip('"') == release and platform.machine() == 'x86_64', 'wrong system LLVM target')
	def query(*args):
		return subprocess.check_output([config, *args], env=env, text=True).strip()
	version = query('--version')
	require(int(version.split('.')[0]) == major, 'wrong system LLVM major')
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
		require(not any(part.lower() == 'llvm' or part.lower().startswith('libllvm') for part in rel.parts), 'bundled LLVM payload refused: '+str(rel))
		require(not str(rel).startswith('usr/include/llvm'), 'LLVM headers refused')


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
	return [name.decode() for name in needed]
