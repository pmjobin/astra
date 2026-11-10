#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Focused C0/Astra owning-slot probes; no inherited/full-source count credit."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from run import C0_SHA256, ROOT, WORK, git, sha, write

BASELINE = 'c99a96a'
ITEM = '''class Item {
	int code;
	init(int code) { this.code = code; }
	int read() { return this.code; }
}
'''
TAKE = '''	var first = values.take(0);
	var second = values.take(0);
	return first.read() + second.read();
'''
CASES = {
	'empty-field-slots': ITEM+'''class Items {
	private owned Item[slots] data;
	init() { this.data = new Item[slots]; }
}
int main() { var values = new Items(); return 42; }
''',
	'local-slots': ITEM+'''int main() {
	var values = new Item[slots];
	var a = new Item(20); var b = new Item(22);
	values.append(move a); values.append(move b);
'''+TAKE+'}\n',
	'field-slots': ITEM+'''class Items {
	private owned Item[slots] data;
	init() { this.data = new Item[slots]; }
	bool reserve(int count) { return this.data.reserve(count); }
	void append(owned Item value) { this.data.append(move value); }
	owned Item take(int at) { var value = this.data.take(at); return move value; }
}
int main() {
	var values = new Items();
	if (!values.reserve(2)) return 3;
	var a = new Item(20); var b = new Item(22);
	values.append(move a); values.append(move b);
'''+TAKE+'}\n',
	'original-generic-Bag': ITEM+'''int main() {
	var values = new Bag<Item>();
	if (!values.reserve(2)) return 3;
	var a = new Item(20); var b = new Item(22);
	values.append(move a); values.append(move b);
'''+TAKE+'}\n',
}

CASES['double-transfer'] = CASES['field-slots'].replace('values.append(move b);', 'values.append(move a);')
CASES['missing-move'] = CASES['field-slots'].replace('values.append(move a);', 'values.append(a);')
CASES['borrowed-transfer'] = CASES['field-slots']+'void invalid(Items values, borrowed Item value) { values.append(move value); }\n'
CASES['wrong-element'] = 'class Other { int code; init(int code) { this.code = code; } }\n'+CASES['field-slots'].replace('b = new Item(22)', 'b = new Other(22)')
C0_REJECTS = {'local-slots', 'double-transfer', 'missing-move', 'borrowed-transfer', 'wrong-element'}


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--component', type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	p.add_argument('--version', required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--case', choices=tuple(CASES), action='append')
	p.add_argument('--require-native', action='store_true', help='fail unless every selected C0-positive source also executes natively under Astra')
	a = p.parse_args()
	assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	for path, parent in ((a.build_root, WORK/'build'), (a.runtime_root, WORK/'runtime')):
		assert path.is_absolute() and path.resolve().is_relative_to(parent.resolve())
		path.mkdir(exist_ok=True)
	leaf = a.runtime_root/('slots-'+a.version+'-'+a.mode)
	build = a.build_root/leaf.name
	leaf.mkdir()
	build.mkdir()
	recipe_witness = leaf/'probe-recipe.py.txt'
	recipe_witness.write_bytes(Path(__file__).read_bytes())
	recipe_sha256 = sha(recipe_witness)
	identity = json.loads(a.component.with_suffix('.identity.json').read_text())
	assert sha(a.component) == identity['sha256'] and identity['identity']['argv'][1] == '-'+a.mode
	historical = []
	for group in ('sources', 'tools'):
		for name, expected in identity['identity'][group].items():
			if sha(name) != expected:
				path = Path(name)
				assert group == 'sources' and path.is_relative_to(ROOT)
				assert hashlib.sha256(git('show', BASELINE+':'+str(path.relative_to(ROOT)))).hexdigest() == expected
				historical.append(name)
	providers = a.component.parent
	objects = [providers/(name+'.o') for name in ('args-posix', 'files-posix', 'text-posix', 'text-ops-posix', 'diagnostics-trap')]
	assert all(path.is_file() for path in objects)
	commands = []
	env = dict(os.environ, CCACHE_DISABLE='1')
	for name in ('LD_PRELOAD', 'VALGRIND_OPTS', 'ASTRA_R4_FAIL_SIZE'):
		env.pop(name, None)
	def run(argv, name, expected=None):
		argv = list(map(str, argv))
		start = time.monotonic()
		with (leaf/(name+'.stdout')).open('wb') as out, (leaf/(name+'.stderr')).open('wb') as err:
			process = subprocess.Popen(['/usr/bin/time', '-v', '-o', str(leaf/(name+'.time')), *argv], cwd=build, env=env, stdout=out, stderr=err, start_new_session=True)
			timed_out = False
			try:
				code = process.wait(120)
			except subprocess.TimeoutExpired:
				timed_out = True
				os.killpg(process.pid, signal.SIGKILL)
				code = process.wait()
		commands.append(dict(name=name, argv=argv, exit=code, timed_out=timed_out, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		write(leaf/'commands.json', commands)
		assert not timed_out and (expected is None or code == expected), (name, code)
		return code
	rows = []
	for name, text in CASES.items():
		if a.case and name not in a.case: continue
		source = leaf/(name+'.astra')
		source.write_text(text)
		inputs = [source, ROOT/'lib/astra/base/errors.astra']
		if name == 'original-generic-Bag': inputs.append(ROOT/'lib/astra/collections/bag.astra')
		oracle = build/(name+'-C0')
		links = [word for obj in objects for word in ('--link-object', obj)]
		valid = name not in C0_REJECTS
		run([a.compiler, '-'+a.mode, *inputs, *links, '-o', oracle], name+'-C0-build', 0 if valid else 1)
		if valid:
			run([oracle], name+'-C0-execute', 42)
			run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', oracle], name+'-C0-memory', 42)
			assert all(value in (leaf/(name+'-C0-memory.stderr')).read_bytes() for value in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
		physical = build/(name+'.ll')
		sentinel = b'Focused owner-slot output sentinel\n'
		physical.write_bytes(sentinel)
		code = run([a.component, '--native', physical, *inputs], name+'-Astra-native')
		stages = run([a.component, '--shared-stages', *inputs], name+'-Astra-stages')
		row = dict(name=name, inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], C0_valid=valid, C0_ELF_sha256=sha(oracle) if valid else None, C0_exit=42 if valid else None, C0_unsuppressed_memory=valid, native_exit=code, stage_exit=stages, destination_preserved=physical.read_bytes() == sentinel if code else False, Astra_native_execution=None)
		if not valid: assert code != 0
		if code != 0:
			assert row['destination_preserved']
		else:
			run(['opt', '-passes=verify', '-disable-output', physical], name+'-verify', 0)
			optimized = build/(name+'-optimized.ll')
			run(['opt', '-passes=default<'+a.mode+'>', '-S', physical, '-o', optimized], name+'-optimize', 0)
			run(['opt', '-passes=verify', '-disable-output', optimized], name+'-optimized-verify', 0)
			obj = build/(name+'.o')
			run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], name+'-object', 0)
			exe = build/(name+'-Astra')
			run(['cc', '-no-pie', obj, *objects, '-o', exe], name+'-link', 0)
			run([exe], name+'-Astra-execute', 42)
			run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-Astra-memory', 42)
			assert all(value in (leaf/(name+'-Astra-memory.stderr')).read_bytes() for value in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
			for stream in ('stdout', 'stderr'):
				assert (leaf/(name+'-Astra-execute.'+stream)).read_bytes() == (leaf/(name+'-C0-execute.'+stream)).read_bytes()
			row.update(Astra_native_execution=42, Astra_unsuppressed_memory=True, raw_LLVM_sha256=sha(physical), optimized_LLVM_sha256=sha(optimized), object_sha256=sha(obj), Astra_ELF_sha256=sha(exe))
		rows.append(row)
		assert sha(Path(__file__)) == recipe_sha256
		write(leaf/'result.json', dict(status='PARTIAL', profile=a.mode, component_sha256=sha(a.component), recipe_sha256=recipe_sha256, recipe_witness=str(recipe_witness), baseline_commit=git('rev-parse', BASELINE).decode().strip(), historical_source_bindings=historical, programs=rows, scope='Focused owner-slot probes only; no 340/71/full-original source or milestone qualification credit. Historical compiler bindings are explicitly labelled; changed implementation is not called rebuilt.'))
		print(name, 'C0=42' if valid else 'C0 rejects', 'Astra native='+str(code), 'stages='+str(stages), flush=True)
		if a.require_native and valid: assert row['Astra_native_execution'] == 42 and stages == 0, name


if __name__ == '__main__':
	main()
