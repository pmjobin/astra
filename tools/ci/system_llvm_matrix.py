#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Record the actual header declarations, enum ABI and imported shared symbols."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from common import ROOT, clean_environment, external, require, run, sha, write
from system_llvm import rhel9


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--identity', type=Path, required=True)
	p.add_argument('--native', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	a = p.parse_args()
	runtime = external(a.runtime)
	llvm = json.loads(a.identity.read_text())['material']['system_llvm']
	env = clean_environment()
	includes = b''.join(('#include <'+name+'>\n').encode() for name in ('llvm-c/Core.h', 'llvm-c/Analysis.h', 'llvm-c/Target.h', 'llvm-c/TargetMachine.h', 'llvm-c/Transforms/PassBuilder.h'))
	header = subprocess.check_output(['cc', '-E', '-P', '-x', 'c', '-I'+llvm['include'], '-'], input=includes, env=env)
	(runtime/'header-api.txt').write_bytes(header)
	imports, _ = run(['nm', '-u', a.native], runtime/'imports', env)
	used = sorted(set(re.findall(rb'\b(LLVM[A-Za-z0-9_]+)(?:@[^\s]+)?\s*$', imports, re.M)))
	bindings = re.findall(rb'extern\(C\)[^;]*?\b(LLVM[A-Za-z0-9_]+)\(', (ROOT/'compiler/backend/llvm/capi.astra').read_bytes())
	api = {}
	for name in sorted(set(used+bindings)):
		declarations = re.findall(rb'(?:^|[;}\n])\s*([^;{}]*?\b'+name+rb'\s*\([^;{}]*?\))\s*;', header, re.M)
		declarations = [item for item in declarations if item[:item.index(name)].strip()]
		require(len(declarations) == 1, 'missing or ambiguous header API: '+name.decode())
		api[name.decode()] = re.sub(rb'\s+', b' ', declarations[0]).decode().strip()
	declared = set(api)
	exports = subprocess.check_output(['nm', '-D', '--defined-only', llvm['library']['path']], env=env)
	exported = set(name.decode() for name in re.findall(rb'\b(LLVM[A-Za-z0-9_]+)(?:@[^\s]+)?\s*$', exports, re.M))
	require(set(name.decode() for name in used) <= exported, 'missing runtime C API exports')
	rpm_target = llvm['major'] == 23 or rhel9(llvm['os_release'])
	if rpm_target:
		version = 'LLVM_'+str(llvm['major'])+'.1'
		versioned = {name.decode() for name in re.findall(rb'\b(LLVM[A-Za-z0-9_]+)@@'+re.escape(version.encode())+rb'$', exports, re.M)}
		require(declared <= versioned, 'missing '+version+' exports: '+str(sorted(declared-versioned)))
	enums = {name.decode():re.sub(rb'\s+', b' ', body).decode() for body, name in re.findall(rb'typedef enum\s*\{([^{}]*?)\}\s*(LLVM[A-Za-z0-9_]+)\s*;', header)}
	require('LLVMOpcode' in enums and 'LLVMTypeKind' in enums, 'missing C enum ABI')
	verification, _ = run(['rpm', '-V', llvm['runtime_package']] if rpm_target else ['dpkg', '--verify', llvm['runtime_package']], runtime/'package-integrity', env)
	if not rpm_target:
		ledger = subprocess.check_output(['dpkg-query', '--control-show', llvm['runtime_package'], 'md5sums'], env=env)
		rows = dict(line.split(None, 1)[::-1] for line in ledger.decode().splitlines())
		library = Path(llvm['library']['path'])
		require(hashlib.md5(library.read_bytes(), usedforsecurity=False).hexdigest() == rows[str(library).lstrip('/')], 'system LLVM package checksum mismatch')
	else:
		require(not verification.strip(), 'system library package has modified files')
	write(runtime/'result.json', dict(status='SYSTEM_LLVM_HEADER_SYMBOL_MATRIX_RECORDED', LLVM=llvm, imported_functions=[name.decode() for name in used], declarations=api, enums=enums, header_preprocessed_sha256=sha(runtime/'header-api.txt'), full_export_table_sha256=hashlib.sha256(exports).hexdigest(), scope='Header prototypes and runtime symbol availability; branch/LP64 executable ABI witness and actual semantic/physical tests are separate gates.'))
	print('SYSTEM_LLVM_HEADER_SYMBOL_MATRIX_RECORDED', len(api), len(enums))


if __name__ == '__main__':
	main()
