#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Fresh native additions, independent C/C0 executions and unsuppressed memory."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-llvm'))
from oracle import memory, inspect


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for key in ('component', 'compiler', 'build', 'runtime', 'frozen'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--case', action='append')
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.build, a.runtime, a.frozen))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256']
	assert all(sha(path) == h for path, h in identity['identity']['sources'].items())
	assert all(sha(path) == h for path, h in identity['identity']['tools'].items())
	assert sha(a.compiler) == '30865ad8a9d1652b63ad882f1e29031c76ac13204212f822b44235cb07df10de'
	commands, results = [], []
	def run(argv, name, expected=0, timeout=180):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], cwd=a.build, capture_output=True, timeout=timeout, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, argv)), exit=r.returncode, name=name,
			monotonic_start=start, monotonic_end=time.monotonic(),
			stdout_sha256=hashlib.sha256(r.stdout).hexdigest(), stderr_sha256=hashlib.sha256(r.stderr).hexdigest()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr[-3000:].decode(errors='replace'))
		return r
	items = json.loads((a.frozen/'selection.json').read_text())
	for item in items:
		name = item['name']
		if a.case and name not in a.case:
			continue
		source = Path(item['source_path']); assert sha(source) == item['source_sha256']
		product = a.build/(name+'-'+a.mode)
		products = dict(raw=product.with_suffix('.raw.ll'), ir=product.with_suffix('.ll'), object=product.with_suffix('.o'), executable=product, reference=product.with_suffix('.c0'))
		admission = run([a.component, '--nativeabi-admit', a.mode, a.runtime/'unused', source], name+'-admit').stdout
		assert admission.startswith(b'astra-flow/4\nSTATUS 0 0\n')
		ssa = run([a.component, '--nativeabi-ssa', a.mode, a.runtime/'unused', source], name+'-ssa').stdout
		for command, key in [('--llvm-raw', 'raw'), ('--llvm-ir', 'ir'), ('--emit-obj', 'object')]:
			run([a.component, command, a.mode, products[key], source], name+'-'+key)
		text = products['raw'].read_text()
		assert not re.search(r'\b(?:nsw|nuw|exact|inbounds|noalias|nonnull|dereferenceable|readonly|nocapture|fast|reassoc|nnan|ninf|nsz|arcp|afn|contract|undef|poison)\b', text)
		assert re.search(r'target triple = "x86_64-[^"]*linux', text)
		if item['family'] != 'c':
			inspect(products['raw'].read_bytes(), ssa)
		run(['llvm-as', products['raw'], '-o', product.with_suffix('.bc')], name+'-llvm-as')
		run(['opt', '-passes=verify', '-disable-output', products['ir']], name+'-opt')
		elf = run(['readelf', '-h', products['object']], name+'-ELF').stdout
		assert b'ELF64' in elf and b'Advanced Micro Devices X86-64' in elf and b'REL (Relocatable file)' in elf
		run(['nm', '-a', products['object']], name+'-symbols')
		run(['objdump', '-dr', products['object']], name+'-disassembly')
		companion = source.with_suffix('.c'); links = []
		if companion.exists():
			obj = a.build/(name+'-gcc.o')
			run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-include', ROOT/'tests/selfhost-nativeabi/target.h', '-c', companion, '-o', obj], name+'-C-compile')
			links = [obj]
			products['C-source'] = companion; products['C-object'] = obj
		run(['gcc', products['object'], *links, '-o', product], name+'-link')
		actual = run([product], name+'-execute', item['expected_exit'])
		assert actual.stdout.decode() == item['expected_stdout'] and actual.stderr.decode() == item['expected_stderr']
		if name in {'c-export-fp', 'c-mixed-pointer', 'c-export-i32-edges', 'c-borrowed-noescape'}:
			obj = product.with_suffix('.c0.o')
			run([a.compiler, '-'+a.mode, '-c', source, '-o', obj], name+'-C0-object')
			run(['gcc', obj, *links, '-o', products['reference']], name+'-C0-link')
			products['C0-object'] = obj
		else:
			extra = [arg for obj in links for arg in ('--link-object', obj)]
			run([a.compiler, '-'+a.mode, source, *extra, '-o', products['reference']], name+'-C0-build')
		reference = run([products['reference']], name+'-C0-execute', item['expected_exit'])
		assert (reference.stdout, reference.stderr) == (actual.stdout, actual.stderr)
		memories = {}
		for label, exe in [('native', product), ('C0', products['reference'])]:
			v = run(['valgrind', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe], name+'-memory-'+label, item['expected_exit'])
			assert v.stdout == actual.stdout
			memories[label] = memory(v.stderr, item['expected_trace'])
		assert memories['native']['observed_trace'] == memories['C0']['observed_trace']
		if companion.exists() and shutil.which('clang'):
			obj = product.with_suffix('.clang.o'); exe = product.with_suffix('.clang')
			run(['clang', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-include', ROOT/'tests/selfhost-nativeabi/target.h', '-c', companion, '-o', obj], name+'-clang-compile')
			run(['clang', products['object'], obj, '-o', exe], name+'-clang-link')
			second = run([exe], name+'-clang-execute', item['expected_exit']); assert (second.stdout, second.stderr) == (actual.stdout, actual.stderr)
			products['clang-object'] = obj; products['clang-executable'] = exe
		results.append(dict(**item, result='PASS', mode=a.mode, component_sha256=sha(a.component), c0_sha256=sha(a.compiler), source_ssa_sha256=hashlib.sha256(ssa).hexdigest(), admission_sha256=hashlib.sha256(admission).hexdigest(), target=re.search(r'target triple = "([^"]+)"', text)[1], layout=re.search(r'target datalayout = "([^"]+)"', text)[1], products={k:dict(path=str(v), bytes=v.stat().st_size, sha256=sha(v)) for k, v in products.items()}, memory=memories))
		(a.runtime/'results.json').write_text(json.dumps(results, indent=2)+'\n')
		print(name, a.mode, 'PASS', flush=True)
	if not a.case:
		assert len(results) >= 12 and len({x['source_sha256'] for x in results}) == len(results)
	(a.runtime/'result.json').write_text(json.dumps(dict(status='DEVELOPMENT' if a.case else 'PASS', mode=a.mode, executions=len(results), cases=results), indent=2)+'\n')


if __name__ == '__main__':
	main()
