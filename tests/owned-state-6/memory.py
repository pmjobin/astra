# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Instrument verified Astra LLVM with ASan; Clang ASan/UBSan the C boundaries.
UBSan does not instrument native Astra arithmetic: that scope is not claimed.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
sys.dont_write_bytecode = True
from execute import ROOT, HERE, APPS, LIBS


def main(compiler_path, emitter_path, output_path):
	compiler, emitter, output = map(lambda p: Path(p).resolve(), [compiler_path, emitter_path, output_path])
	assert not output.is_relative_to(ROOT)
	output.mkdir(parents=True, exist_ok=True)
	out = Path(tempfile.mkdtemp(prefix='run-', dir=output)); rows = []
	sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
	receipt = dict(compiler_sha256=sha(compiler), emitter_sha256=sha(emitter), checks=rows, products={},
		coverage='ASan: generated native LLVM; ASan/UBSan: selected C providers; no native arithmetic UBSan',
		sources={str(p.relative_to(ROOT)):sha(p) for p in [*LIBS, APPS/'model.astra', HERE/'memory.py', HERE/'observer.c', HERE/'arena-edges.astra', HERE/'record-resources.c', APPS/'nested-resource-event.astra', APPS/'record-batch-rollback.astra', HERE/'owning-lazy.astra', HERE/'owning-checked-lazy.astra', HERE/'owning-lazy-lifecycle.astra']})
	def save(): (out/'checks.json').write_text(json.dumps(receipt, indent=2)+'\n')
	def run(command, target=None):
		p = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, timeout=120,
			env=dict(os.environ, ASAN_OPTIONS='detect_leaks=1:halt_on_error=1', UBSAN_OPTIONS='halt_on_error=1', PYTHONDONTWRITEBYTECODE='1'))
		row = dict(command=list(map(str, command)), actual=p.returncode, stderr=p.stderr.decode(errors='replace'), passed=p.returncode == 0 and not p.stderr)
		if target is not None:
			target.write_bytes(p.stdout); row['stdout_file'] = str(target); row['stdout_sha256'] = sha(target)
		else: row['stdout'] = p.stdout.decode(errors='replace')
		rows.append(row); save(); assert row['passed'], row
		return p
	providers = []
	for name in ['text', 'files', 'args', 'observer', 'record-resources']:
		source = HERE/(name+'.c') if name in ['observer', 'record-resources'] else ROOT/f'lib/astra/platform/{name}-posix.c'
		obj = out/(name+'.o'); providers.append(obj)
		run(['clang', '-std=c11', '-g', '-O1', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined', '-c', source, '-o', obj])
	for name in ['lazy-diagnostic-card', 'retryable-settings-reader', 'diagnostic-queue-editor', 'cached-diagnostic-rewriter', 'arena-edges', 'nested-resource-event', 'record-batch-rollback', 'owning-lazy', 'owning-checked-lazy', 'owning-lazy-lifecycle']:
		inputs = [HERE/'arena-edges.astra', ROOT/'lib/astra/memory/byte-arena.astra', ROOT/'lib/astra/base/errors.astra'] if name == 'arena-edges' else [APPS/(name+'.astra'), APPS/'model.astra', *LIBS]
		if name in ['nested-resource-event', 'record-batch-rollback']:
			inputs = [APPS/(name+'.astra'), LIBS[0], '--vapi', ROOT/'tests/own-field/fixtures/resources.vapi']
		if name in ['owning-lazy', 'owning-checked-lazy', 'owning-lazy-lifecycle']:
			inputs = [HERE/(name+'.astra'), LIBS[0]]
		raw, marked, instrumented, obj, exe = [out/(name+s) for s in ['.ll', '-marked.ll', '-asan.ll', '.o', '']]
		run([emitter, '--emit', raw, *inputs])
		assert 'define i32 @main(' in raw.read_text(), 'missing executable root'
		text = raw.read_text(); text, count = re.subn(r'^(define [^\n]+)\{$', r'\1sanitize_address {', text, flags=re.M)
		assert count > 0; marked.write_text(text)
		run(['opt', '-passes=verify', '-disable-output', marked])
		run(['opt', '-passes=default<O2>,asan', '-S', marked, '-o', instrumented])
		assert '__asan_report_' in instrumented.read_text(), 'native code was not ASan instrumented'
		run(['opt', '-passes=verify', '-disable-output', instrumented])
		run(['llc', '-O2', '-filetype=obj', '-relocation-model=pic', instrumented, '-o', obj])
		run(['clang', '-fsanitize=address,undefined', obj, *providers, '-o', exe])
		args = []
		if name == 'retryable-settings-reader': args = [out/'settings.bin']
		if name == 'cached-diagnostic-rewriter':
			source, dest = out/'rewrite.input', out/'rewrite.output'; source.write_bytes(b'\xff'); args = [source, dest]
		run([exe, *args])
		if name == 'cached-diagnostic-rewriter': assert dest.read_bytes() == b'repaired=\xc3\xa9\0recordOK\0\n'
		receipt['products'][exe.name] = sha(exe); save()
	print(f'{len(rows)} sanitizer checks; {len(receipt["products"])} generated programs; receipts: {out}')

if __name__ == '__main__': main(*sys.argv[1:])
