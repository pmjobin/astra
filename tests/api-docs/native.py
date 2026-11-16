#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Current complete-compiler docs isolation and comment-equivalence qualification."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT.parent/'codex/work/astra'
sys.path.insert(0, str(ROOT/'tests/selfhost-ownership-syntax-27b'))
from support import execute, output_path, sha, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--products', type=Path, required=True)
	p.add_argument('--toolchain', type=Path, required=True)
	p.add_argument('--runtime', type=Path, required=True)
	p.add_argument('--build', type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), action='append', help='Explicit host profiles; final qualification requires both')
	a = p.parse_args()
	products = json.loads(a.products.read_text())['products']
	selected = set(a.mode or ('O0', 'O2'))
	assert selected <= set(products)
	products = {mode:products[mode] for mode in ('O0', 'O2') if mode in selected}
	assert all(row['status'] == 'BUILT_NOT_QUALIFIED' and sha(row['path']) == row['sha256'] for row in products.values())
	assert all(sha(row[kind]['path']) == row[kind]['sha256'] for row in products.values() for kind in ('native', 'doc'))
	runtime = output_path(a.runtime, WORK/'runtime')
	build = output_path(a.build, WORK/'build')
	runtime.mkdir(parents=True, exist_ok=False)
	build.mkdir(parents=True, exist_ok=False)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	toolchain = json.loads(a.toolchain.read_text())
	assert all(sha(path) == h for path,h in toolchain['tools'].items())
	env = dict(os.environ)
	env.update({key:value for key,value in toolchain['environment'].items() if value is not None})
	env.pop('LD_PRELOAD', None)
	env.pop('VALGRIND_OPTS', None)
	assert subprocess.check_output(['llvm-config', '--version'], env=env).strip() == b'23.1.4'
	commands = []
	emitted = {}
	def run(label, argv, expected=0, memory=False, extra_env=None):
		if memory:
			argv = ['valgrind', '--trace-children=yes', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv]
		argv = ['env', '-C', runtime, *argv]
		local = dict(env, **(extra_env or {}))
		result = execute(argv, runtime/label, expected=expected, timeout=300, env=local)
		commands.append(dict(label=label, argv=list(map(str, argv)), result=result, strict_memory=memory, environment_overrides=extra_env or {}))
		write(runtime/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', (label, (runtime/label/'stderr').read_text())
		if memory:
			assert all(marker in (runtime/label/'stderr').read_bytes() for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)')), label
		print(label, result['status'], round(result['seconds'], 3), flush=True)
		return (runtime/label/'stdout').read_bytes()
	plain = 'language astra27b;\nint plus(int left, int right) { return left+right; }\nint main() { return plus(20,22); }\n'
	documented = plain.replace('int plus', '/// Adds two scalar values.\n/// @param left First value.\n/// @param right Second value.\n/// @return Their sum.\nint plus')
	for name,text in [('plain.astra', plain), ('documented.astra', documented)]:
		(runtime/name).write_text(text)
	sources = {str(runtime/name):sha(runtime/name) for name in ('plain.astra', 'documented.astra')}
	for host_mode, product in products.items():
		compiler = Path(product['path'])
		# Every imported LLVM API is an observed trap. A normal help invocation
		# must trip LLVMShutdown, proving that the interposer is active.
		undefined = subprocess.check_output(['nm', '-u', product['native']['path']], text=True)
		names = sorted(set(re.findall(r'\b(LLVM[A-Za-z0-9_]+)(?:@[^\s]+)?\s*$', undefined, re.M)))
		assert 'LLVMShutdown' in names and 'LLVMContextCreate' in names
		trap_source = runtime/(host_mode+'-llvm-trap.c')
		trap_source.write_text('#include <stdlib.h>\n#include <unistd.h>\n'+''.join('__attribute__((noreturn)) void '+name+'(void) { (void)write(2,"LLVM_CALL:'+name+'\\n",sizeof("LLVM_CALL:'+name+'\\n")-1); _Exit(91); }\n' for name in names))
		trap = build/(host_mode+'-llvm-trap.so')
		run(host_mode+'-trap-build', ['cc', '-shared', '-fPIC', '-std=c11', '-Wall', '-Wextra', '-Werror', trap_source, '-o', trap])
		sources[str(trap_source)] = sha(trap_source)
		emitted[str(trap)] = sha(trap)
		run(host_mode+'-trap-control', [compiler, '--help'], expected=91, extra_env={'LD_PRELOAD':str(trap)})
		assert b'LLVM_CALL:LLVMShutdown' in (runtime/(host_mode+'-trap-control')/'stderr').read_bytes()
		run(host_mode+'-doc-backend-guard-control', [product['doc']['path'], '--help'], expected=127)
		assert b'forbidden LLVM backend call' in (runtime/(host_mode+'-doc-backend-guard-control')/'stderr').read_bytes()
		doc_output = build/(host_mode+'-doc.json')
		run(host_mode+'-docs-no-LLVM', [compiler, 'doc', '--output', doc_output, 'documented.astra'], extra_env={'LD_PRELOAD':str(trap)})
		assert not (runtime/(host_mode+'-docs-no-LLVM')/'stderr').read_bytes()
		emitted[str(doc_output)] = sha(doc_output)
		run(host_mode+'-docs-memory', [compiler, 'doc', '--output', build/(host_mode+'-memory.json'), 'documented.astra'], memory=True)
		semantic = []
		for variant in ('plain', 'documented'):
			destination = build/(host_mode+'-'+variant+'.json')
			run(host_mode+'-'+variant+'-docs', [compiler, 'doc', '--output', destination, variant+'.astra'])
			document = json.loads(destination.read_text())
			semantic.append([{key:row[key] for key in ('id', 'canonical_name', 'owner', 'signature', 'type_contract', 'throws', 'parameters', 'type_parameters', 'generic_constraints', 'attributes', 'availability')} for row in document['symbols']])
			emitted[str(destination)] = sha(destination)
		assert semantic[0] == semantic[1]
		for target_mode in ('O0', 'O2'):
			irs = []
			objects = []
			for variant in ('plain', 'documented'):
				label = host_mode+'-'+target_mode+'-'+variant
				ir = build/(label+'.ll')
				obj = build/(label+'.o')
				run(label+'-IR', [compiler, '--emit-llvm', '-'+target_mode, '-o', ir, variant+'.astra'])
				run(label+'-verify', ['opt', '-passes=verify', '-disable-output', ir])
				run(label+'-object', [compiler, '-c', '-'+target_mode, '-o', obj, variant+'.astra'], memory=variant == 'documented')
				exe = build/label
				run(label+'-link', ['cc', '-no-pie', obj, '-o', exe])
				run(label+'-native', [exe], expected=42)
				run(label+'-memory', [exe], expected=42, memory=True)
				irs.append(ir.read_bytes())
				objects.append(obj.read_bytes())
				for path in (ir, obj, exe): emitted[str(path)] = sha(path)
			assert irs[0] == irs[1], (host_mode, target_mode, 'comments changed LLVM')
			assert objects[0] == objects[1], (host_mode, target_mode, 'comments changed object bytes')
	assert all(sha(path) == h for path,h in {**sources, **emitted}.items())
	assert all(sha(row['path']) == row['sha256'] for row in products.values())
	assert all(sha(row[kind]['path']) == row[kind]['sha256'] for row in products.values() for kind in ('native', 'doc'))
	write(runtime/'result.json', dict(status='CURRENT_COMPLETE_COMPILER_DOCS_ISOLATION_AND_COMMENT_EQUIVALENCE_PASS', profiles=list(products), products=products, sources=sources, emit_products=emitted, commands_sha256=sha(runtime/'commands.json'), toolchain_receipt_sha256=sha(a.toolchain), scope='Explicit complete compiler profiles, actual LLVM interposition with positive control, semantic/IR/object equivalence with and without doc trivia, native execution and strict all-kinds memory. Final qualification requires both host profiles and the separate broader ABI/owner/physical suites.'))


if __name__ == '__main__':
	main()
