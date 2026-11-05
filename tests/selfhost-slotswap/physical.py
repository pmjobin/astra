#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Six LLVM-valid record-slot alternatives checked by an external runtime oracle.

These candidates are post-emission mutations. They are not represented as inputs
to Astra's retained-module verifier. The inherited physical audit stays separate.
"""
import argparse
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import time
import xml.etree.ElementTree as ET
from state import ROOT, RUNTIME, BUILD, read, sha

EXCHANGE = re.compile(r'(?P<all>  (?P<left>%\w+) = load \{ ptr, i32 \}, ptr (?P<lp>%\w+), align 8\n  (?P<right>%\w+) = load \{ ptr, i32 \}, ptr (?P<rp>%\w+), align 8\n  store \{ ptr, i32 \} (?P=right), ptr (?P=lp), align 8\n  store \{ ptr, i32 \} (?P=left), ptr (?P=rp), align 8\n)')


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser(); p.add_argument('--qualification', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--name', default='physical-v1'); a = p.parse_args()
	assert a.name.replace('-','').isalnum()
	leaf = RUNTIME/(a.name+'-'+a.mode); build = BUILD/(a.name+'-'+a.mode); leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	row = next(row for row in read(a.qualification/'results.json') if row['name'] == 'nested-field-local'); assert row['baseline_complete']
	measurements = (a.qualification/'nested-field-local-ABI-probe.stdout').read_text()
	assert 'LAYOUT Parcel 24 8 3\n' in measurements and 'FIELD Parcel weight 8 8 8\n' in measurements
	assert all(sha(s['path']) == s['sha256'] for s in row['sources']) and all(sha(x['path']) == x['sha256'] for x in row['products'].values())
	raw = Path(row['products']['raw']['path']); text = raw.read_text(); match = EXCHANGE.search(text); assert match
	left, right, lp, rp = [match[x] for x in ('left', 'right', 'lp', 'rp')]
	assert lp != rp
	load_left = f'  {left} = load {{ ptr, i32 }}, ptr {lp}, align 8\n'
	load_right = f'  {right} = load {{ ptr, i32 }}, ptr {rp}, align 8\n'
	store_left = f'  store {{ ptr, i32 }} {right}, ptr {lp}, align 8\n'
	store_right = f'  store {{ ptr, i32 }} {left}, ptr {rp}, align 8\n'
	variants = {
		'overwritten-second-snapshot': load_left+f'  store {{ ptr, i32 }} {left}, ptr {rp}, align 8\n'+load_right+store_left+store_right,
		'one-sided-owner-commit': load_left+load_right+f'  store {{ ptr, i32 }} {left}, ptr {lp}, align 8\n'+store_right,
		'record-base-with-stale-count': load_left+load_right+f'  %slotswap.count = extractvalue {{ ptr, i32 }} {left}, 1\n  %slotswap.partial = insertvalue {{ ptr, i32 }} {right}, i32 %slotswap.count, 1\n'+store_left.replace(right, '%slotswap.partial')+store_right,
		'false-same-slot-resolution': load_left+load_right.replace(rp,lp)+store_left+store_right.replace(rp,lp),
		'early-record-allocation-retirement': load_left+load_right+f'  %slotswap.base = extractvalue {{ ptr, i32 }} {left}, 0\n  call void @free(ptr %slotswap.base)\n'+store_left+store_right,
		'payload-copy-instead-of-owner-only': load_left+load_right+f'  %slotswap.base = extractvalue {{ ptr, i32 }} {right}, 0\n  %slotswap.weight = getelementptr i8, ptr %slotswap.base, i64 248\n  store i64 0, ptr %slotswap.weight, align 8\n'+store_left+store_right,
	}
	commands = []; results = []; env = dict(os.environ, CCACHE_DISABLE='1'); env.pop('VALGRIND_OPTS', None); env.pop('LD_PRELOAD', None)
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *map(str, argv)], cwd=build, capture_output=True, env=env, timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str,argv)), exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands,indent=2)+'\n'); return r
	assert run([row['products']['native']['path']], 'valid-twin').returncode == 42
	for label, replacement in variants.items():
		path = build/(label+'.ll'); path.write_text(text[:match.start()]+replacement+text[match.end():])
		assert run(['opt', '-passes=verify', '-disable-output', path], label+'-verify').returncode == 0
		obj = path.with_suffix('.o'); elf = path.with_suffix('')
		assert run(['llc', '-'+a.mode, '-relocation-model=pic', '-filetype=obj', path, '-o', obj], label+'-lower').returncode == 0
		assert run(['gcc', obj, '-o', elf], label+'-link').returncode == 0
		xml = leaf/(label+'.xml')
		r = run(['valgrind', '--command-line-only=yes', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--track-origins=yes', '--xml=yes', '--xml-file='+str(xml), elf], label+'-execute')
		errors = len(ET.parse(xml).getroot().findall('error'))
		assert r.returncode != 42 or errors > 0
		assert sha(raw) == row['products']['raw']['sha256'] and run([row['products']['native']['path']], label+'-restored-twin').returncode == 42
		results.append(dict(category=label, LLVM_valid=True, runtime_exit=r.returncode, Valgrind_errors=errors, independently_rejected=True, IR_sha256=sha(path), object_sha256=sha(obj), ELF_sha256=sha(elf)))
		print(a.mode, label, 'LLVM_VALID REJECTED', flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, twin=row, mutations=results, commands=commands, recipe_sha256=sha(__file__), boundary='External LLVM verifier and independent explicit source assertions / unsuppressed Valgrind. Astra retained-module consumption is not claimed.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
