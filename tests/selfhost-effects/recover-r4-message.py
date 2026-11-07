#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute the complete unchanged original Utf8Message Class, with C0 control."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_message_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-message-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stdout[-1500:], r.stderr[-2500:]); return r
	original = ROOT/'lib/astra/text/utf8-message.astra'; data = original.read_bytes(); first = data.index(b'class Utf8Message {'); last = data.index(b'\n}\n', first)+3; view = leaf/'message-view.astra'; view.write_bytes(data[first:last])
	syntax = load_module('r4_message_syntax', ROOT/'tests/selfhost-effects/recover-r3-original-view.py'); old = syntax.declarations(run([C0, '--dump-syntax', original], 'original-AST').stdout.decode()); new = syntax.declarations(run([C0, '--dump-syntax', view], 'view-AST').stdout.decode()); assert len(new) == 1 and new[0] in old and new[0].startswith('(class "Utf8Message"')
	caller = leaf/'caller.astra'; caller.write_text('int main() { var first = new Utf8Message("é\\0x"); var empty = new Utf8Message(""); if (first.text != "é\\0x") return 3; if (empty.text != "") return 4; return 42; }\n')
	full = run([a.component, '--native', build/'full.ll', caller, ROOT/'lib/astra/base/errors.astra', original], 'Astra-full-module-attempt', range(9))
	exe = build/'C0'; run([C0, '-'+a.mode, caller, original, ROOT/'lib/astra/base/errors.astra', '-o', exe], 'C0-build'); run([exe], 'C0-execute', (42,)); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], 'C0-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
	llvm = build/'Astra.ll'; llvm.write_text('Original Class sentinel\n'); sentinel = sha(llvm); native = run([a.component, '--native', llvm, caller, view], 'Astra-view-attempt', range(9)); emitted = native.returncode == 0; native_exe = None
	if emitted:
		run(['opt', '-passes=verify', '-disable-output', llvm], 'LLVM-verify'); optimized = build/'optimized.ll'; run(['opt', '-S', '-passes=default<'+a.mode+'>', llvm, '-o', optimized], 'LLVM-optimize'); run(['opt', '-passes=verify', '-disable-output', optimized], 'optimized-verify'); obj = build/'Astra.o'; native_exe = build/'Astra'; run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], 'Astra-object'); run(['cc', '-no-pie', obj, '-o', native_exe], 'Astra-link'); run([native_exe], 'Astra-execute', (42,)); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', native_exe], 'Astra-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
	else: assert sha(llvm) == sentinel
	result = dict(status='ORIGINAL_CLASS_EXECUTED' if emitted else 'ORIGINAL_CLASS_DEFERRED', profile=a.mode, component_sha256=sha(a.component), original=str(original), original_sha256=sha(original), start_byte=first, end_byte=last, fragment_sha256=hashlib.sha256(data[first:last]).hexdigest(), view=str(view), view_sha256=sha(view), AST_byte_exact=True, AST_sha256=hashlib.sha256(new[0].encode()).hexdigest(), excluded_declarations=['InvalidUtf8 (unexercised Error subclass)', 'utf8_message (unexercised factory declaration)'], full_module_exit=full.returncode, full_module_stdout=full.stdout.decode(), C0_actual_execution=42, C0_ELF_sha256=sha(exe), Astra_emitted=emitted, Astra_actual_execution=42 if emitted else None, Astra_ELF_sha256=sha(native_exe) if emitted else None, Astra_LLVM_sha256=sha(llvm) if emitted else None, Astra_stdout=native.stdout.decode(), limitation='This tests one complete real original Class and its readonly property, including empty and embedded-NUL UTF-8 snapshots. It is not original flow_number or full builder qualification.')
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n'); print(json.dumps(result, indent=2), flush=True)


if __name__ == '__main__':
	main()
