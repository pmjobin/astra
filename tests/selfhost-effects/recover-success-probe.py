#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Caller-controlled success cells against unchanged Astra/C0 emitted bodies.

The appended LLVM main is an independent test adapter, never Astra ELF credit.
The original emitted modules remain byte-exact separate artifacts.
"""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, bounded_run, read, sha

PROGRAMS = {
	'scalar': 'int make(bool fail) throws Error { if (fail) { throw new Error("kept"); } return 17; }\nint main() { return 0; }\n',
	'buffer': 'owned int[] make(bool fail) throws Error { var value = new int[2]; if (fail) { throw new Error("kept"); } return move value; }\nint main() { return 0; }\n',
	'Class': 'class Parcel { init() {} }\nowned Parcel make(bool fail, bool empty) throws Error { if (fail) { throw new Error("kept"); } if (empty) return null; var value = new Parcel(); return move value; }\nint main() { return 0; }\n'
}


def adapter(raw, shape, failure):
	text = raw.decode(); entries = re.findall(r'define internal fastcc ptr @([\w.]+)\(ptr[^\n]*, i1', text); assert len(entries) == 1, entries
	text, count = re.subn(r'(define i32 )@main\(', r'\1@source.main(', text); assert count == (1 if re.search(r'define i32 @main\(', raw.decode()) else 0)
	carrier = 'i32' if shape == 'scalar' else '{ptr, i32}' if shape == 'buffer' else 'ptr'
	poison = '324508639' if shape == 'scalar' else '{ptr inttoptr (i64 305419896 to ptr), i32 999}' if shape == 'buffer' else 'inttoptr (i64 305419896 to ptr)'
	arguments = 'i1 '+str(failure).lower()+(', i1 true' if shape == 'Class' else '')
	cleanup = '''  %descriptor = load ptr, ptr %error
  %destroy.cell = getelementptr {ptr,ptr,ptr}, ptr %descriptor, i32 0, i32 1
  %destroy = load ptr, ptr %destroy.cell
  call fastcc void %destroy(ptr %error)
  call void @free(ptr %error)
'''
	if shape == 'buffer':
		check = '''  %data = extractvalue {ptr,i32} %got, 0
  %length = extractvalue {ptr,i32} %got, 1
  %data.ok = icmp '''+('eq' if failure else 'ne')+''' ptr %data, inttoptr (i64 305419896 to ptr)
  %count.ok = icmp eq i32 %length, '''+('999' if failure else '2')+'''
  %cell.ok = and i1 %data.ok, %count.ok
'''
	else:
		expected = poison if failure else '17' if shape == 'scalar' else 'null'
		check = '  %cell.ok = icmp eq '+carrier+' %got, '+expected+'\n'
	finish = '  %exit = select i1 %cell.ok, i32 42, i32 4\n  ret i32 %exit\n'
	if not failure and shape == 'buffer':
		finish = '  br i1 %cell.ok, label %dispose, label %bad\ndispose:\n  call void @free(ptr %data)\n  ret i32 42\n'
	main = '\ndefine i32 @main() {\nentry:\n  %slot = alloca '+carrier+'\n  store '+carrier+' '+poison+', ptr %slot\n  %error = call fastcc ptr @'+entries[0]+'(ptr %slot, '+arguments+')\n  %expected.channel = icmp '+('ne' if failure else 'eq')+' ptr %error, null\n  br i1 %expected.channel, label %inspect, label %bad\ninspect:\n  %got = load '+carrier+', ptr %slot\n'+check+(cleanup if failure else '')+finish+'bad:\n  ret i32 4\n}\n'
	return (text+main).encode()


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('success_cell_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('success-cell-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']; assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, name, expected):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == expected, (name, r.stdout[-1000:], r.stderr[-2500:]); return r
	for shape, source in PROGRAMS.items():
		path = leaf/(shape+'.astra'); path.write_text(source); inputs = [path, ROOT/'lib/astra/base/errors.astra']; astra = build/(shape+'-Astra-original.ll'); run([a.component, '--native', astra, *inputs], shape+'-Astra-emit', 0); oracle = run([C0, '-O0', '--dump-llvm', *inputs], shape+'-C0-emit', 0); c0 = build/(shape+'-C0-original.ll'); c0.write_bytes(oracle.stdout)
		for compiler, original in [('Astra', astra), ('C0', c0)]:
			for failure in (False, True):
				name = shape+'-'+compiler+('-error' if failure else '-success'); raw = build/(name+'.ll'); raw.write_bytes(adapter(original.read_bytes(), shape, failure)); run(['opt', '-passes=verify', '-disable-output', raw], name+'-verify', 0); optimized = build/(name+'-optimized.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', raw, '-o', optimized], name+'-optimize', 0); run(['opt', '-passes=verify', '-disable-output', optimized], name+'-optimized-verify', 0); obj = build/(name+'.o'); exe = build/name; run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], name+'-object', 0); run(['cc', '-no-pie', obj, '-o', exe], name+'-link', 0); run([exe], name+'-execute', 42)
				memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-memory', 42); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
				rows.append(dict(shape=shape, producer=compiler, error=failure, original_LLVM_sha256=sha(original), test_adapter_LLVM_sha256=sha(raw), ELF_sha256=sha(exe), success_cell='Unchanged poison on error; complete scalar/buffer/null-Class publication on success')); print(a.mode, name, 'caller-controlled cell verified; independent ABI probe only', flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='CALLER_CONTROLLED_ABI_PROBE_ONLY', target_profile=a.mode, component_sha256=sha(a.component), Astra_effect_ELFs=0, results=rows, limitation='Handwritten LLVM caller adapter; emitted target bodies remain byte-exact original artifacts. Not part of new-source native program counts.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
