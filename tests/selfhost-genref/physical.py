#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Seven LLVM-valid alternatives to the new recursive-member binding witness."""
import argparse
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import time
import xml.etree.ElementTree as ET
from state import RUNTIME, BUILD, read, sha


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser(); p.add_argument('--qualification', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args()
	leaf = RUNTIME/('physical-'+a.version+'-'+a.mode); directory = BUILD/leaf.name; leaf.mkdir(exist_ok=False); directory.mkdir(exist_ok=False)
	row = next(row for row in read(a.qualification/'results.json') if row['name'] == 'recursive-member-binding'); assert row['baseline_complete']
	assert all(sha(s['path']) == s['sha256'] for s in row['sources']) and all(sha(x['path']) == x['sha256'] for x in row['products'].values())
	raw = Path(row['products']['raw']['path']); text = raw.read_text(); selected = []
	for function in re.finditer(r'^define (?:internal )?i32 (?P<fn>@[^ (]+)\(ptr (?P<receiver>%[\w.]+), i32 (?P<depth>%[\w.]+)\)[^\n]*\n.*?^}\n', text, re.M | re.S):
		call = re.search(r'^  (?P<result>%[\w.]+) = call i32 '+re.escape(function['fn'])+r'\(ptr (?P<receiver>%[\w.]+), i32 (?P<argument>%[\w.]+)\)\n', function[0], re.M)
		if call: selected.append((function, call))
	assert len(selected) == 1; function, call = selected[0]; body = function[0]
	def change_body(candidate): return text[:function.start()]+candidate+text[function.end():]
	def replace_call(candidate): return change_body(body[:call.start()]+candidate+body[call.end():])
	variants = {
		'stale-recursive-receiver': replace_call(call[0].replace('ptr '+call['receiver'], 'ptr null', 1)),
		'omitted-recursive-edge': replace_call('  '+call['result']+' = add i32 0, 3\n'),
		'duplicated-recursive-edge': replace_call(call[0]+call[0].replace(call['result']+' =', '%genref.repeated =', 1)),
	}
	entry = re.search(r'call i32 '+re.escape(function['fn'])+r'\(ptr [\w.%]+, i32 3\)', text); assert entry
	variants['stale-entry-depth'] = text[:entry.start()]+entry[0].replace('i32 3', 'i32 0')+text[entry.end():]
	branch = re.search(r'icmp eq i32 [^,\n]+, 0', body); assert branch
	variants['wrong-recursive-stop-predicate'] = change_body(body[:branch.start()]+branch[0].replace('icmp eq', 'icmp sgt')+body[branch.end():])
	variants['lost-recursive-owner-retirement'] = re.sub(r'^  call void @free\(ptr [^\n]+\)(?: #[0-9]+)?\n', '', text, flags=re.M)
	receiver = function['receiver']; split = body.index('\n')+1; header = body[:split].replace('ptr '+receiver, 'i64 '+receiver, 1)
	changed = re.sub(re.escape(receiver)+r'(?![\w.])', '%genref.receiver.ptr', body[split:]); label = re.search(r'^[\w.]+:[^\n]*\n', changed, re.M); assert label
	changed = changed[:label.end()]+'  %genref.receiver.ptr = inttoptr i64 '+receiver+' to ptr\n'+changed[label.end():]
	abi = change_body(header+changed)
	pattern = r'(?P<indent>^  )(?P<result>%[\w.]+) = call i32 '+re.escape(function['fn'])+r'\(ptr (?P<receiver>%[\w.]+), i32 (?P<argument>[%\w.]+)\)\n'
	ordinal = [0]
	def convert(match):
		ordinal[0] += 1; bits = '%genref.receiver.bits.'+str(ordinal[0])
		return '  '+bits+' = ptrtoint ptr '+match['receiver']+' to i64\n'+match[0].replace('ptr '+match['receiver'], 'i64 '+bits, 1)
	abi, count = re.subn(pattern, convert, abi, flags=re.M); assert count >= 2
	variants['recursive-borrow-channel-integer-ABI'] = abi
	commands, results = [], []; env = dict(os.environ, CCACHE_DISABLE='1'); env.pop('VALGRIND_OPTS', None); env.pop('LD_PRELOAD', None)
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *map(str, argv)], cwd=directory, capture_output=True, env=env, timeout=180)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	assert run([row['products']['native']['path']], 'valid-twin').returncode == 86
	for name, candidate in variants.items():
		assert candidate != text; path = directory/(name+'.ll'); path.write_text(candidate)
		assert run(['opt', '-passes=verify', '-disable-output', path], name+'-LLVM-verify').returncode == 0
		obj, elf = path.with_suffix('.o'), path.with_suffix('')
		assert run(['llc', '-'+a.mode, '-relocation-model=pic', '-filetype=obj', path, '-o', obj], name+'-lower').returncode == 0
		assert run(['gcc', obj, '-o', elf], name+'-link').returncode == 0
		xml = leaf/(name+'.xml'); r = run(['valgrind', '--command-line-only=yes', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', '--track-origins=yes', '--xml=yes', '--xml-file='+str(xml), elf], name+'-execute'); errors = len(ET.parse(xml).getroot().findall('error'))
		abi_rejected = name == 'recursive-borrow-channel-integer-ABI' and re.search(r'^define (?:internal )?i32 '+re.escape(function['fn'])+r'\(ptr ', candidate, re.M) is None
		assert r.returncode != 86 or errors > 0 or abi_rejected, name
		assert sha(raw) == row['products']['raw']['sha256'] and run([row['products']['native']['path']], name+'-restored-twin').returncode == 86
		results.append(dict(category=name, LLVM_valid=True, runtime_exit=r.returncode, Valgrind_errors=errors, independent_ABI_rejected=abi_rejected, independently_rejected=True, IR_sha256=sha(path), object_sha256=sha(obj), ELF_sha256=sha(elf))); print(a.mode, name, 'LLVM_VALID INDEPENDENTLY_REJECTED', flush=True)
	assert len(results) == 7
	(leaf/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, mutations=results, commands=commands, recipe_sha256=sha(__file__), boundary='External LLVM verification, source assertions independently matched to C0, the existing private pointer receiver ABI, and unsuppressed Valgrind. Faulted post-emission modules are separate from Astra retained-module audit and normal-return memory qualification.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
