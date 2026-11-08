#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Actual Astra source execution and independently LLVM-valid module mutations."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

SOURCE = '''[CCode(text_abi = "utf8-i32")]
extern(C) int proof_text_byte(borrowed string text, int index);
class Value {
	private int number;
	init(int number) { this.number = number; }
	int read() { return this.number; }
}
class Text {
	readonly string snapshot;
	init(string input) { this.snapshot = input; }
	property string text { get { return this.snapshot; } }
}
class Box {
	private owned Text content;
	init(owned Text content) { this.content = move content; }
	bool valid() { return this.content.text == "kept"; }
}
bool observed(int value, [CallerLineNumber] int line) { return value == 42 && line > 0; }
int computed(int value) {
	var bytes = new u8[3];
	bytes[1] = value as u8;
	return (bytes[1] as int) / 2;
}
int read_value(borrowed Value value) { return value.read(); }
int first(u8[] bytes) { return bytes[0] as int; }
int main() {
	try {
		u8[2] left = {42, 1};
		u8[2] right = {9, 4};
		if (first(slice(left, 0, 1)) != 42 || first(slice(right)) != 9) return 3;
		if (!observed(computed(84))) return 4;
		if (proof_text_byte("A\\0B", 2) != 66) return 5;
		var value = new Value(42);
		var handle = shared_acquire(move value);
		var retained = shared_clone(handle);
		if (read_value(shared_borrow(retained)) != 42) return 6;
		var text = new Text("kept");
		var box = new Box(move text);
		if (!box.valid()) return 7;
		var bytes = new u8[0];
		var message = utf8_message(bytes);
		if (message.text != "") return 8;
		return 42;
	} catch (Error caught) { return 9; }
}
'''

CATEGORIES = [
	'counted foreign argument length', 'source caller-line argument',
	'UTF8 entry guard', 'shared clone actual handle', 'indexed read actual index',
	'indexed store actual RHS', 'bounds helper pointer flags',
	'slice descriptor count', 'fixed array actual allocation extent',
	'cast poison flag', 'integer zero-divisor guard', 'nested field actual base',
	'short-circuit phi incoming value', 'distinct fixed array backing allocations',
]


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--component', type=Path)
	p.add_argument('--oracle-only', action='store_true')
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	if not a.oracle_only:
		assert a.component is not None
		identity = read(a.component.with_suffix('.identity.json'))
		assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
		assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	paths = load_module('frontier_physical_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('frontier-physical-'+a.version+'-'+a.mode)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	source = leaf/'program.astra'
	source.write_text(SOURCE)
	inputs = [source, ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/text/utf8-message.astra']
	provider = leaf/'provider.c'
	provider.write_text('#include <stdint.h>\nint32_t proof_text_byte(const unsigned char *p, int32_t n, int32_t i) { return i >= 0 && i < n ? p[i] : -1; }\n')
	commands = []
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stdout[-2500:], r.stderr.splitlines()[:4])
		return r
	obj = build/'provider.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', obj], 'provider-build')
	oracle = build/'C0'
	run([C0, '-'+a.mode, *inputs, '--link-object', obj, '-o', oracle], 'C0-build')
	c0 = run([oracle], 'C0-execute', (42,))
	memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', oracle], 'C0-memory', (42,))
	assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr and memory.stdout == c0.stdout
	if a.oracle_only:
		(leaf/'result.json').write_text(json.dumps(dict(status='INDEPENDENT_C0_FRONTIER_FIXTURE', profile=a.mode, inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], C0_ELF_sha256=sha(oracle), actual_exit=42, Astra_native_credit=0), indent=2)+'\n')
		print(a.mode, 'independent C0 frontier fixture and returning memory passed; zero Astra execution credit', flush=True)
		return
	stage = run([a.component, '--shared-stages', *inputs], 'source-stage-mutations', (42,))
	assert b'SHARED_SSA_VALID' in stage.stdout
	physical = build/'Astra.ll'
	run([a.component, '--native', physical, *inputs], 'Astra-emit')
	run(['opt', '-passes=verify', '-disable-output', physical], 'Astra-verify')
	optimized = build/'Astra-optimized.ll'
	run(['opt', '-passes=default<'+a.mode+'>', '-S', physical, '-o', optimized], 'Astra-optimize')
	run(['opt', '-passes=verify', '-disable-output', optimized], 'Astra-optimized-verify')
	object_file = build/'Astra.o'
	run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', object_file], 'Astra-object')
	exe = build/'Astra'
	run(['cc', '-no-pie', object_file, obj, '-o', exe], 'Astra-link')
	actual = run([exe], 'Astra-execute', (42,))
	assert actual.stdout == c0.stdout and actual.stderr == c0.stderr
	for label, binary in [('Astra', exe)]:
		memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', binary], label+'-memory', (42,))
		assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr and memory.stdout == actual.stdout
	run([a.component, '--frontier-physical', build, *inputs], 'module-mutations')
	variants = []
	for category, meaning in enumerate(CATEGORIES):
		path = build/('frontier-physical-'+str(category)+'.ll')
		run(['opt', '-passes=verify', '-disable-output', path], 'physical-verify-'+str(category))
		variants.append(dict(category=category, meaning=meaning, LLVM_sha256=sha(path)))
	(leaf/'result.json').write_text(json.dumps(dict(status='ACTUAL_FRONTIER_MODULE_PROOF', component_sha256=sha(a.component), profile=a.mode, inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], Astra_raw_LLVM_sha256=sha(physical), Astra_ELF_sha256=sha(exe), C0_ELF_sha256=sha(oracle), actual_exit=42, LLVM_valid_physical=variants, source_semantic_markers=[line for line in stage.stdout.decode().splitlines() if line.startswith('SEMANTIC ')], original_flow_number_execution_credit=0, limitation='One new source witness through actual Astra→LLVM→ELF, matched C0 and returning unsuppressed memory. Fourteen independently LLVM-valid whole-module physical alternatives rejected with positive twins. This fixture neither replaces nor qualifies the original full-source flow_number gate.'), indent=2)+'\n')
	print(a.mode, 'actual frontier source and 14 LLVM-valid full-module alternatives qualified', flush=True)


if __name__ == '__main__':
	main()
