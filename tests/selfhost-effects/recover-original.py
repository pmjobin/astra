#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actually attempt an unchanged original throwing function with real dependencies."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

BASE = '48eb69926ad5735864696d15963d7396ce181683'


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--provider-build', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('original_recover_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('original-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']; assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	name = 'compiler/semantic/flow-query.astra'; original = ROOT/name; data = original.read_bytes(); committed = subprocess.check_output(['git', 'show', BASE+':'+name], cwd=ROOT); assert data == committed
	start = data.index(b'void flow_number(Utf8ByteBuilder output, int value) throws Error {\n'); end = data.index(b'\n}\n', start)+3; body = data[start:end]; function = leaf/'unchanged-flow-number.astra'; function.write_bytes(body); assert function.read_bytes() == committed[start:end]
	driver = leaf/'caller.astra'; driver.write_text('int main() { try { var output = new Utf8ByteBuilder(); flow_number(output, 42); if (output.byte_count() != 3) return 4; var message = output.snapshot(); if (message.text == " 42") return 42; return 3; } catch (Error caught) { return 5; } }\n')
	libraries = load_module('original_recover_libraries', ROOT/'tests/selfhost-typecore/build.py'); inputs = [function, driver, ROOT/'compiler/source/source.astra', *[ROOT/('lib/astra/'+name+'.astra') for name in libraries.LIBRARIES]]; assert len(inputs) == len(set(inputs))
	def run(argv, name, allowed):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stdout[-1500:], r.stderr[-2000:]); return r
	links = []
	for provider in libraries.PROVIDERS:
		path = a.provider_build/(provider+'.o'); assert path.is_file(); links += ['--link-object', path]
	c0 = build/'C0'; run([C0, '-'+a.mode, *inputs, *links, '-o', c0], 'C0-build', {0}); run([c0], 'C0-execute-original-function', {42}); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', c0], 'C0-memory', {42}); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
	target = build/'Astra.ll'; target.write_text('Original function output sentinel\n'); before = sha(target); attempt = run([a.component, '--native', target, *inputs], 'Astra-original-native-attempt', {0, 1, 2, 3, 4, 5, 6, 7, 8}); emitted = attempt.returncode == 0
	if emitted:
		run(['opt', '-passes=verify', '-disable-output', target], 'Astra-verify', {0}); obj = build/'Astra.o'; exe = build/'Astra'; run(['llc', '-filetype=obj', '-'+a.mode, target, '-o', obj], 'Astra-object', {0}); provider_objects = links[1::2]; run(['cc', '-no-pie', obj, *provider_objects, '-o', exe], 'Astra-link', {0}); run([exe], 'Astra-execute-original-function', {42})
	else: assert sha(target) == before
	result = dict(status='ORIGINAL_FUNCTION_EXECUTED' if emitted else 'ORIGINAL_FUNCTION_NATIVE_DEFERRED', component_sha256=sha(a.component), profile=a.mode, source=dict(path=str(original), full_file_sha256=sha(original), pinned_commit=BASE, slice_start_byte=start, slice_end_byte=end, slice_sha256=hashlib.sha256(body).hexdigest(), exact_original_bytes=True), inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], C0_ELF_sha256=sha(c0), C0_actual_execution=42, Astra_emitted=emitted, Astra_actual_execution=42 if emitted else None, destination_preserved=not emitted, first_failure_stdout=attempt.stdout.decode(errors='replace')[:2000], first_failure_stderr=attempt.stderr.decode(errors='replace')[:2000], limitation='Only an actual Astra-emitted execution can satisfy G9. C0 executes the unchanged function with the real Utf8ByteBuilder, scalar formatter and original source dependencies; no substitute Class or no-op helper is used. This separate slice does not replace frozen whole-cohort identity checks.')
	(leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n'); print(result['status'], flush=True)


if __name__ == '__main__':
	main()
