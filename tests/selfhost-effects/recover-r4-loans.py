#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C0 Class-field loans and containing-owner invalidation controls."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def corpus():
	item = 'class Item { private int value; init(int value) { this.value = value; } int number() { return this.value; } } '
	box = 'class Box { owned Item item; init(owned Item item) { this.item = move item; } void replace(owned Item replacement) { this.item = move replacement; } } '
	main = 'var item = new Item(42); var box = new Box(move item); '
	return {
		'Class-field-borrow-legal':(True, True, item+box+'int inspect(Item item) { return item.number(); } int main() { '+main+'return inspect(box.item); }\n'),
		'Class-name-borrow-legal':(True, True, 'class Value { private int value; init() { this.value = 42; } int number() { return this.value; } } int inspect(Value value) { return value.number(); } int main() { var value = new Value(); return inspect(value); }\n'),
		'Class-field-before-owner-consumption':(False, False, item+box+'int dispose(owned Box value) { return 17; } int inspect(Item item, int extra) { return item.number(); } int main() { '+main+'return inspect(box.item, dispose(move box)); }\n'),
		'Class-field-after-owner-consumption':(False, False, item+box+'int dispose(owned Box value) { return 17; } int inspect(int extra, Item item) { return item.number(); } int main() { '+main+'return inspect(dispose(move box), box.item); }\n'),
		'Class-name-before-owner-consumption':(False, False, 'class Value { private int value; init() { this.value = 42; } int number() { return this.value; } } int dispose(owned Value value) { return 17; } int inspect(Value value, int extra) { return value.number(); } int main() { var value = new Value(); return inspect(value, dispose(move value)); }\n'),
		'Class-field-before-containing-replacement':(False, False, item+box+'int replace(Box value) { var replacement = new Item(1); value.replace(move replacement); return 17; } int inspect(Item item, int extra) { return item.number(); } int main() { '+main+'return inspect(box.item, replace(box)); }\n'),
		'Class-field-and-containing-alias':(False, False, item+box+'int inspect(Item item, Box parent) { var replacement = new Item(1); parent.replace(move replacement); return item.number(); } int main() { '+main+'return inspect(box.item, box); }\n'),
		'borrowed-Class-local':(None, False, item+box+'int main() { '+main+'borrowed Item held = box.item; return held.number(); }\n'),
		'borrowed-Class-local-after-release':(False, False, item+box+'int main() { '+main+'borrowed Item held = box.item; release box; return held.number(); }\n'),
	}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_loans_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-loans-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	if a.component:
		identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, name):
		argv = list(map(str, argv)); start = time.monotonic(); env = dict(os.environ, CCACHE_DISABLE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=env, capture_output=True, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	for name, (legal, native_expected, text) in corpus().items():
		source = leaf/(name+'.astra'); source.write_text(text); c0 = build/(name+'-C0'); r = run([C0, '-'+a.mode, source, '-o', c0], name+'-C0-build'); assert r.returncode in (0, 1); C0_legal = r.returncode == 0
		if legal is not None: assert C0_legal == legal, (name, r.stderr)
		row = dict(name=name, source_sha256=sha(source), C0_legal=C0_legal, native_expected=native_expected)
		if C0_legal:
			assert run([c0], name+'-C0-execute').returncode == 42; memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', c0], name+'-C0-memory'); assert memory.returncode == 42 and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr; row['C0_ELF_sha256'] = sha(c0)
		if a.component:
			ir = build/(name+'.ll'); ir.write_text('Class loan output sentinel\n'); before = sha(ir); native = run([a.component, '--native', ir, source], name+'-Astra-emit'); row.update(Astra_exit=native.returncode, Astra_emitted=native.returncode == 0, Astra_stdout=native.stdout.decode(), Astra_stderr=native.stderr.decode()); rows.append(row); (leaf/'result.json').write_text(json.dumps(dict(status='CLASS_LOAN_CONTROLS_IN_PROGRESS', programs=rows), indent=2)+'\n'); assert (native.returncode == 0) == native_expected, row
			if native_expected:
				assert C0_legal; optimized = build/(name+'-optimized.ll'); obj = build/(name+'.o'); exe = build/(name+'-Astra'); assert run(['opt', '-passes=verify', '-disable-output', ir], name+'-verify').returncode == 0; assert run(['opt', '-passes=default<'+a.mode+'>', '-S', ir, '-o', optimized], name+'-optimize').returncode == 0; assert run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], name+'-object').returncode == 0; assert run(['cc', '-no-pie', obj, '-o', exe], name+'-link').returncode == 0; assert run([exe], name+'-Astra-execute').returncode == 42; memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-Astra-memory'); assert memory.returncode == 42 and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr; row.update(Astra_ELF_sha256=sha(exe), raw_LLVM_sha256=sha(ir))
			else: assert sha(ir) == before
		else: rows.append(row)
		(leaf/'result.json').write_text(json.dumps(dict(status='C0_CLASS_LOAN_CONTROLS' if not a.component else 'INDEPENDENT_CLASS_LOAN_CONTROLS', profile=a.mode, component_sha256=sha(a.component) if a.component else None, programs=rows, primary_native_credit=0, limitation='C0-invalid programs are never executed by Astra, even if an admission bug emits LLVM. Borrowed locals without a parent-root certificate remain deferred. Complete positive controls require actual independent C0/native execution and unsuppressed Valgrind.'), indent=2)+'\n'); print(a.mode, name, 'C0 legal', C0_legal, row.get('Astra_exit'), flush=True)


if __name__ == '__main__':
	main()
