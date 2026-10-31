#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Evaluate selected C int header constants through an explicit host C compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

IDENTIFIER = re.compile(r'[A-Za-z_][A-Za-z_0-9]*\Z')
TARGET = 'x86_64-linux-gnu-lp64'


def unique(pairs):
	result = {}
	for key, value in pairs:
		if key in result:
			raise ValueError('duplicate JSON key: ' + key)
		result[key] = value
	return result


def digest(data):
	return hashlib.sha256(data).hexdigest()


def generate(profile_path, scratch, cc):
	data = profile_path.read_bytes()
	profile = json.loads(data, object_pairs_hook=unique)
	if set(profile) != {'format', 'target', 'headers', 'constants'} or profile['format'] != 'astra-c-header-profile/1' or profile['target'] != TARGET:
		raise ValueError('requires astra-c-header-profile/1 and selected GNU x86-64 Linux LP64 target')
	headers, constants = profile['headers'], profile['constants']
	if not isinstance(headers, list) or not 1 <= len(headers) <= 16 or len(set(headers)) != len(headers):
		raise ValueError('requires 1..16 unique explicit headers')
	for header in headers:
		if not isinstance(header, str) or not re.fullmatch(r'[A-Za-z_0-9./-]+', header) or Path(header).is_absolute() or any(p in ('', '.', '..') for p in header.split('/')):
			raise ValueError('header must be an explicit portable relative include name')
	if not isinstance(constants, list) or not 1 <= len(constants) <= 128:
		raise ValueError('requires 1..128 selected constants')
	seen = set()
	for item in constants:
		if not isinstance(item, dict) or set(item) != {'macro', 'name'} or not all(isinstance(item[k], str) and IDENTIFIER.fullmatch(item[k]) for k in item):
			raise ValueError('constant requires exact macro and source name identifiers')
		if item['name'] in seen:
			raise ValueError('duplicate generated source name')
		seen.add(item['name'])
	env = dict(os.environ, CCACHE_DISABLE='1', SOURCE_DATE_EPOCH='0', LC_ALL='C')
	def run(arguments, cwd):
		process = subprocess.run([str(cc), *map(str, arguments)], cwd=cwd, env=env, capture_output=True, timeout=60)
		if process.returncode:
			raise ValueError('C compiler rejected selected header contract:\n' + process.stderr.decode(errors='replace'))
		return process.stdout
	version = run(['--version'], scratch).decode().splitlines()[0]
	target = run(['-dumpmachine'], scratch).decode().strip()
	if not target.startswith('x86_64-') or 'linux' not in target:
		raise ValueError('selected compiler must target native x86-64 Linux')
	includes = ['#include <stdint.h>', '#include <limits.h>', '#include <stdio.h>', *['#include "' + h + '"' for h in headers]]
	checks = ['_Static_assert(sizeof(void *) == 8 && sizeof(long) == 8 && sizeof(int) == 4 && CHAR_BIT == 8, "selected LP64 model");']
	for item in constants:
		macro = item['macro']
		checks += [f'_Static_assert(_Generic(({macro}), int: 1, default: 0), "{macro}: requires exact C int constant");', f'_Static_assert(({macro}) >= INT32_MIN && ({macro}) <= INT32_MAX, "{macro}: constant out of i32 range");']
	probe = '\n'.join([*includes, *checks, 'int main(void) {', *['\tprintf("%d\\n", (int)(' + c['macro'] + '));' for c in constants], '\treturn 0;', '}']) + '\n'
	with tempfile.TemporaryDirectory(prefix='c-headers-', dir=scratch) as temporary:
		work = Path(temporary)
		(work / 'probe.c').write_text(probe)
		flags = ['-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic', '-Werror=date-time', '-ffile-prefix-map=' + str(work) + '=<scratch>', '-ffile-prefix-map=' + str(profile_path.parent) + '=<profile>', '-I', profile_path.parent]
		preprocessed = run([*flags, '-E', '-P', work / 'probe.c'], work)
		run([*flags, work / 'probe.c', '-o', work / 'probe'], work)
		result = subprocess.run([work / 'probe'], env=env, capture_output=True, timeout=30)
		if result.returncode:
			raise ValueError('header constant evaluation failed')
		values = result.stdout.decode('ascii').splitlines()
		if len(values) != len(constants) or any(not re.fullmatch(r'-?[0-9]+', v) or not -(2**31) <= int(v) < 2**31 for v in values):
			raise ValueError('invalid C constant evaluation output')
	identity = dict(format='astra-c-header-contract/1', target=TARGET, compiler=version, compiler_target=target,
		profile_sha256=digest(data), preprocessed_sha256=digest(preprocessed), generator_sha256=digest(Path(__file__).read_bytes()),
		constants=[dict(item, value=int(value)) for item, value in zip(constants, values)])
	abi = digest(json.dumps(identity, sort_keys=True, separators=(',', ':')).encode())
	prefix = 'astra_header_' + abi + '_'
	native = ['// Explicit evaluated C header constants; astra-c-header/1.']
	code = ['/* Explicit evaluated C header constants; astra-c-header/1. */', '#include "bindings.h"', *includes, *checks]
	header = ['/* Typed constant getter declarations; astra-c-header/1. */', '#ifndef ASTRA_HEADER_' + abi.upper(), '#define ASTRA_HEADER_' + abi.upper(), '#include <stdint.h>', '#ifdef __cplusplus', 'extern "C" {', '#endif']
	for item, value in zip(constants, values):
		name, macro = item['name'], item['macro']
		symbol = prefix + name
		native += ['const int Header_' + name + ' = ' + value + ';', '[CImport(name="' + symbol + '",header="bindings.h")]', 'int header_' + name + '();']
		header.append('int32_t ' + symbol + '(void);')
		code += [f'_Static_assert(({macro}) == ({value}), "stale header constant: {macro}");', 'int32_t ' + symbol + '(void) { return (int32_t)(' + value + '); }']
	header += ['#ifdef __cplusplus', '}', '#endif', '#endif']
	files = {name: ('\n'.join(lines) + '\n').encode() for name, lines in [('bindings.astra', native), ('bindings.c', code), ('bindings.h', header)]}
	identity.update(abi_identity=abi, products={name: digest(content) for name, content in files.items()})
	files['contract.json'] = (json.dumps(identity, indent=2, sort_keys=True) + '\n').encode()
	return files


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument('--profile', type=Path, required=True)
	parser.add_argument('--work', type=Path, required=True, help='explicit external scratch/build directory')
	parser.add_argument('--cc', default='cc')
	group = parser.add_mutually_exclusive_group(required=True)
	group.add_argument('--output', type=Path)
	group.add_argument('--verify', type=Path)
	args = parser.parse_args()
	try:
		args.work.mkdir(parents=True, exist_ok=True)
		files = generate(args.profile.resolve(), args.work.resolve(), args.cc)
		if args.verify:
			for name, content in files.items():
				path = args.verify / name
				if path.is_symlink() or path.read_bytes() != content:
					raise ValueError('stale or altered header product: ' + name)
		else:
			args.output.mkdir(parents=True, exist_ok=False)
			for name, content in files.items():
				(args.output / name).write_bytes(content)
		print('PASS: verified evaluated C int header constants' if args.verify else 'PASS: generated evaluated C int header constants')
	except (ValueError, OSError, subprocess.TimeoutExpired, TypeError) as failure:
		parser.exit(1, 'astra-c-header: ' + str(failure) + '\n')


if __name__ == '__main__':
	main()
