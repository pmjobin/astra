#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Mutate actual ELF/package-boundary inputs; never treat fixtures as installers."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tools/ci'))
from common import clean_environment, external, require, run, write
from system_llvm import audit_elf, audit_payload


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--native', type=Path, required=True)
	p.add_argument('--identity', type=Path, required=True)
	p.add_argument('--output', type=Path, required=True)
	a = p.parse_args()
	out = external(a.output)
	llvm = json.loads(a.identity.read_text())['material']['system_llvm']
	env = clean_environment()
	controls = []
	for name in ('usr/lib/astra/llvm/libLLVM.so', 'usr/lib/libLLVM.a', 'usr/include/llvm-c/Core.h'):
		stage = out/('payload-'+str(len(controls)))
		path = stage/name
		path.parent.mkdir(parents=True)
		path.write_bytes(b'FORBIDDEN_COPY_CONTROL')
		try:
			audit_payload(stage)
		except ValueError:
			controls.append(name)
		else:
			raise AssertionError('LLVM payload accepted')
	for name, data in [('hidden-elf', a.native.read_bytes()), ('hidden-archive', b'!<arch>\n')]:
		stage = out/name
		stage.mkdir()
		(stage/'innocent.bin').write_bytes(data)
		try:
			audit_payload(stage)
		except ValueError:
			controls.append(name)
		else:
			raise AssertionError('hidden binary accepted')
	stage = out/'symlink'
	stage.mkdir()
	(stage/'library').symlink_to('/usr/lib/libLLVM.so')
	try:
		audit_payload(stage)
	except ValueError:
		controls.append('private-symlink')
	else:
		raise AssertionError('payload symlink accepted')
	for name, options in [('rpath', ['--force-rpath', '--set-rpath', '/tmp/private-llvm']), ('runpath', ['--set-rpath', '/tmp/private-llvm']), ('wrong-major', ['--replace-needed', llvm['soname'], 'libLLVM.so.999']), ('missing-symbol-library', ['--replace-needed', llvm['soname'], 'libc.so.6']), ('architecture', [])]:
		path = out/name
		shutil.copyfile(a.native, path)
		if options:
			run(['patchelf', *options, path], out/(name+'-mutation'), env)
		else:
			data = bytearray(path.read_bytes())
			data[18:20] = b'\xb7\x00'
			path.write_bytes(data)
		try:
			audit_elf(path, llvm, out/(name+'-audit'), env)
		except ValueError:
			controls.append(name)
		else:
			raise AssertionError('bad ELF accepted: '+name)
	bad = out/'wrong-source.json'
	write(bad, dict(package_commit='0'*40))
	result = subprocess.run([sys.executable, '-B', ROOT/'tools/ci/package.py', '--object', a.native, '--handoff', bad, '--system-llvm', '--development', '--kind', 'rpm', '--build', out/'never-build', '--runtime', out/'never-runtime'], capture_output=True)
	(out/'wrong-source.stderr').write_bytes(result.stderr)
	require(result.returncode != 0 and b'wrong package source commit' in result.stderr, 'wrong source commit accepted')
	controls.append('wrong-source-commit')
	write(out/'result.json', dict(status='SYSTEM_LLVM_NEGATIVE_CONTROLS_PASS', controls=controls, scope='Actual copied native ELF mutated; forbidden payload fixtures refused. No install or strict memory credit.'))
	print('SYSTEM_LLVM_NEGATIVE_CONTROLS_PASS', len(controls))


if __name__ == '__main__':
	main()
