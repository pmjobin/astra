#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused source stages and independent C0, including exact original frontiers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def corpus(path):
	caller = '''bool observe(bool condition, [CallerFilePath] string file, [CallerLineNumber] int line, [CallerArgumentExpression("condition")] string expression) {
	return condition && file == "@PATH@" && line == 5 && expression == "(20 + 22) == 42";
}
int main() {
	if (observe((20 + 22) == 42)) return 42;
	return 3;
}
'''.replace('@PATH@', str(path/'caller-all.astra'))
	return {
		'array-heap-index': ('''int main() {
	var bytes = new u8[3];
	bytes[0] = 20;
	bytes[1] = 22;
	return (bytes[0] as int) + (bytes[1] as int);
}
''', []),
		'array-int-field': ('''class Values {
	private owned int[] data;
	init() { this.data = new int[3]; }
	int run() { this.data[2] = 42; return this.data[2]; }
}
int main() { var values = new Values(); return values.run(); }
''', []),
		'array-fixed-slice': ('''int read(u8[] bytes) { return bytes[0] as int; }
int main() { u8[4] bytes = {1, 42, 3, 4}; return read(slice(bytes, 1, 1)); }
''', []),
		'array-empty-slice': ('''int read(u8[] bytes) { return len(bytes) + 42; }
int main() { u8[1] bytes = {42}; return read(slice(bytes, 1, 0)); }
''', []),
		'nested-field-receiver': ('''class Text {
	readonly string snapshot;
	init(string text) { this.snapshot = text; }
	property string text { get { return this.snapshot; } }
	int read() { if (this.snapshot == "42") return 42; return 3; }
}
class Box {
	private owned Text child;
	init(owned Text child) { this.child = move child; }
	int read() { if (this.child.text != "42") return 4; return this.child.read(); }
}
int main() { var text = new Text("42"); var box = new Box(move text); return box.read(); }
''', []),
		'integer-guarded-arithmetic': ('''int quotient(int value, int divisor) { return value / divisor; }
int main() {
	int value = -2147483648;
	if (quotient(value, -1) != value) return 3;
	if (value % -1 != 0) return 4;
	if (((value as u32) % 10) as int != 8) return 5;
	if ((192 & 128) != 128) return 6;
	return 42;
}
''', []),
		'original-builder-format': ('''int main() {
	try {
		var builder = new Utf8ByteBuilder();
		if (!append_int(builder, -2147483648)) return 3;
		if (!append_bool(builder, true)) return 4;
		if (!append_u32(builder, 4294967295)) return 5;
		var message = builder.snapshot();
		if (message.text != "-2147483648true4294967295") return 6;
		return 42;
	} catch (Error caught) { return 7; }
}
''', ['text/utf8-message', 'text/utf8-byte-builder', 'text/scalar-format']),
		'original-builder-invalid': ('''int main() {
	try {
		var builder = new Utf8ByteBuilder();
		u8[1] bytes = {255};
		if (!builder.append_bytes(slice(bytes))) return 3;
		var message = builder.snapshot();
		return 4;
	} catch (InvalidUtf8 caught) { if (caught.message == "invalid UTF-8") return 42; return 5; }
}
''', ['text/utf8-message', 'text/utf8-byte-builder']),
		'caller-all': (caller, []),
		'caller-partial': ('''bool observe(int value, [CallerLineNumber] int line, [CallerArgumentExpression("value")] string expression) {
	return value == 42 && line == 99 && expression == "21 * 2";
}
int main() {
	if (observe(21 * 2, 99)) return 42;
	return 3;
}
''', []),
		'counted-C-import': ('''[CCode(text_abi = "utf8-i32")]
extern(C) int proof_text_byte(borrowed string text, int index);
int main() {
	if (proof_text_byte("a\\0z", 1) != 0 || proof_text_byte("a\\0z", 2) != 122 || proof_text_byte("a\\0z", 3) != -1) return 3;
	return 42;
}
''', []),
		'guarded-shared-constructor': ('''class Payload {
	int value;
	init(int value) { this.value = value; }
	int read() { return this.value; }
}
bool valid(borrowed Payload payload, int value) { return payload.read() == value; }
class Guarded {
	private owned shared Payload payload;
	private int value;
	init(owned shared Payload payload, int value) {
		assert_that(valid(shared_borrow(payload), value));
		this.payload = move payload;
		this.value = value;
	}
	int read() { return this.value; }
}
int main() {
	var payload = new Payload(42);
	var handle = shared_acquire(move payload);
	var guarded = new Guarded(move handle, 42);
	return guarded.read();
}
''', ['base/diagnostics']),
		'pointer-and-absent-comparison': ('''class Value {
	init() {}
}
bool same(borrowed Value first, borrowed Value last) { return first == last; }
bool same_handles(borrowed shared Value first, borrowed shared Value last) {
	if (first == null) return last == null;
	if (last == null) return false;
	return same(shared_borrow(first), shared_borrow(last));
}
int main() {
	var value = new Value();
	var handle = shared_acquire(move value);
	var retained = shared_clone(handle);
	if (same_handles(handle, retained)) return 42;
	return 3;
}
''', []),
		'original-UTF8-empty': ('''int main() {
	try {
		var bytes = new u8[0];
		var message = utf8_message(bytes);
		if (message.text == "") return 42;
		return 3;
	} catch (Error caught) { return 4; }
}
''', ['text/utf8-message']),
	}


def main():
	p = argparse.ArgumentParser()
	p.add_argument('--version', required=True)
	p.add_argument('--observer', type=Path, required=True)
	a = p.parse_args()
	assert a.version.isalnum()
	identity = read(a.observer.with_suffix('.identity.json'))
	assert sha(a.observer) == identity['sha256']
	paths = load_module('frontier_source_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = paths.RUNTIME/('frontier-source-'+a.version)
	build = paths.BUILD/leaf.name
	leaf.mkdir()
	build.mkdir()
	commands = []
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv))
		start = time.monotonic()
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout)
		(leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode in allowed, (name, r.returncode, r.stdout[-3000:], r.stderr.splitlines()[:3])
		return r
	provider = leaf/'provider.c'
	provider.write_text('#include <stdint.h>\nint32_t proof_text_byte(const unsigned char *p, int32_t n, int32_t i) { return i >= 0 && i < n ? p[i] : -1; }\n')
	obj = build/'provider.o'
	run(['gcc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', provider, '-o', obj], 'provider-build')
	rows = []
	# Read-only full-population witness first; a successful reduced view never
	# changes the identity or classification of this original attempt.
	prior = read(paths.RUNTIME.parent/'effects25-r5/original-before-O0/result.json')
	inputs = [Path(row['path']) for row in prior['inputs']]
	assert all(sha(row['path']) == row['sha256'] for row in prior['inputs'])
	original = run([a.observer, *inputs], 'full-original-stages', (*range(8), 42, 132, -4))
	boundary = None
	lines = original.stdout.decode().splitlines()
	for i, line in enumerate(lines):
		if line.startswith('SHARED_FLOW '):
			state = list(map(int, line.split()[1:]))
			if state[1] > 0:
				file_hex, first, last = lines[i+1].split()
				source = Path(bytes.fromhex(file_hex).decode())
				first, last = int(first), int(last)
				assert source in inputs
				fragment = source.read_bytes()[first:last]
				boundary = dict(stage=state[0], node=state[1], path=str(source), first=first, last=last, sha256=hashlib.sha256(fragment).hexdigest())
	(leaf/'full-original-result.json').write_text(json.dumps(dict(observer_sha256=sha(a.observer), exit=original.returncode, original_inputs=prior['inputs'], boundary=boundary, Astra_native_credit=0, limitation='Actual current source/Flow/Core/CFG/SSA attempt over the full original dependencies. No target emission or original-function execution credit.'), indent=2)+'\n')
	# Reuse prior read-only selected witnesses only after rechecking every byte
	# against the unchanged live originals and both complete declaration ASTs.
	witness = read(paths.RUNTIME.parent/'effects25-r5/r4-original-view-baseline-O0/result.json')
	views = load_module('frontier_original_AST_views', ROOT/'tests/selfhost-effects/recover-r4-original-view.py')
	for selection in witness['selections']:
		source = Path(selection['original'])
		view = Path(selection['view'])
		assert sha(source) == selection['original_sha256'] and sha(view) == selection['view_sha256']
		data = source.read_bytes()
		fragments = []
		for span in selection['ranges']:
			fragment = data[span['start_byte']:span['end_byte']]
			assert hashlib.sha256(fragment).hexdigest() == span['sha256']
			fragments.append(fragment)
		assert b'\n'.join(fragments) == view.read_bytes()
		old = views.declarations(run([C0, '--dump-syntax', source], view.stem+'-original-AST').stdout.decode())
		selected = views.declarations(run([C0, '--dump-syntax', view], view.stem+'-selected-AST').stdout.decode())
		assert all(declaration in old for declaration in selected)
		assert hashlib.sha256('\n'.join(selected).encode()).hexdigest() == selection['AST_sha256']
	minimal_inputs = [Path(row['path']) for row in witness['inputs']]
	assert all(sha(row['path']) == row['sha256'] for row in witness['inputs'])
	minimal = run([a.observer, *minimal_inputs], 'minimal-original-stages', (*range(8), 42, 132, -4))
	minimal_boundary = None
	lines = minimal.stdout.decode().splitlines()
	for i, line in enumerate(lines):
		if line.startswith('SHARED_FLOW '):
			state = list(map(int, line.split()[1:]))
			if state[1] > 0:
				file_hex, first, last = lines[i+1].split()
				source = Path(bytes.fromhex(file_hex).decode())
				first, last = int(first), int(last)
				assert source in minimal_inputs
				fragment = source.read_bytes()[first:last]
				minimal_boundary = dict(stage=state[0], node=state[1], path=str(source), first=first, last=last, sha256=hashlib.sha256(fragment).hexdigest())
	(leaf/'minimal-original-result.json').write_text(json.dumps(dict(observer_sha256=sha(a.observer), exit=minimal.returncode, original_inputs=witness['inputs'], selections=witness['selections'], boundary=minimal_boundary, Astra_native_credit=0, limitation='Actual source/Flow/Core/CFG/SSA attempt on the minimal AST/byte-exact dependency view. Success here is separate from full-original compilation and grants no native original-function execution credit.'), indent=2)+'\n')
	for name, (text, dependencies) in corpus(leaf).items():
		source = leaf/(name+'.astra')
		source.write_text(text)
		inputs = [source, ROOT/'lib/astra/base/errors.astra', *[ROOT/('lib/astra/'+dependency+'.astra') for dependency in dependencies]]
		stage = run([a.observer, *inputs], name+'-stages', (*range(8), 42, 132, -4))
		stages_valid = stage.returncode == 42 and b'SHARED_SSA_VALID' in stage.stdout
		profiles = []
		for mode in ('O0', 'O2'):
			exe = build/(name+'-'+mode)
			links = ['--link-object', obj]
			if 'base/diagnostics' in dependencies:
				links += ['--link-object', a.observer.parent/'diagnostics-trap.o']
			run([C0, '-'+mode, *inputs, *links, '-o', exe], name+'-'+mode+'-build')
			run([exe], name+'-'+mode+'-execute', (42,))
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-'+mode+'-memory', (42,))
			assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
			profiles.append(dict(mode=mode, ELF_sha256=sha(exe), actual_exit=42))
		rows.append(dict(name=name, source_sha256=sha(source), stages_valid=stages_valid, observer_exit=stage.returncode, actual_stages=['Flow', 'Core', 'CFG', 'SSA'] if stages_valid else [], C0=profiles))
		(leaf/'result.json').write_text(json.dumps(dict(status='FOCUSED_SOURCE_FRONTIER_PREFLIGHT' if all(row['stages_valid'] for row in rows) else 'FOCUSED_SOURCE_FRONTIER_PARTIAL', programs=rows, observer_sha256=sha(a.observer), Astra_native_credit=0, limitation='Actual current stage attempts and independent C0 O0/O2 source semantics and unsuppressed memory. Failed stage attempts remain failures. No Astra target or original-function execution credit.'), indent=2)+'\n')
		print(name, 'stage exit', stage.returncode, 'C0 O0/O2 passed', flush=True)
	assert all(row['stages_valid'] for row in rows), 'Focused source stage failures remain; see the exact individual receipts.'


if __name__ == '__main__':
	main()
