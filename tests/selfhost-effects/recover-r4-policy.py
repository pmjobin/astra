#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C0 policy probes; these never receive Astra-native credit."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def corpus():
	box = 'class Vessel { private owned int[] data; private int used; init(owned int[] data) { this.data = move data; this.used = len(this.data); } bool bump() { this.used = this.used + 1; return false; } int value() { return this.used; } void exchange(owned int[] replacement) { swap(this.data, replacement); this.used = len(this.data); } }\n'
	rows = {
		'discard-false': (True, 'bool ignored() { return false; } int main() { ignored(); return 42; }\n'),
		'discard-scalar': (True, 'int ignored() { return 7; } int main() { ignored(); return 42; }\n'),
		'discard-record': (False, 'struct Pair { int x; bool y; } Pair ignored() { Pair p = {x = 1, y = false}; return p; } int main() { ignored(); return 42; }\n'),
		'discard-buffer': (False, 'owned int[] ignored() { var p = new int[3]; return move p; } int main() { ignored(); return 42; }\n'),
		'discard-class': (False, 'class Vessel { init() {} } owned Vessel ignored() { var p = new Vessel(); return move p; } int main() { ignored(); return 42; }\n'),
		'discard-error': (True, 'bool ignored() throws Error { throw new Error("kept"); } int main() { try { ignored(); return 3; } catch (Error caught) { if (caught.message == "kept") return 42; return 4; } }\n'),
		'field-mixed': (True, box+'int main() { var bytes = new int[41]; var box = new Vessel(move bytes); box.bump(); return box.value(); }\n'),
		'field-exchange': (True, box+'int main() { var bytes = new int[1]; var box = new Vessel(move bytes); var replacement = new int[42]; box.exchange(move replacement); return box.value(); }\n'),
		'field-initialize-late': (False, 'class Vessel { private int x; private int y; init() { this.x = this.y; this.y = 42; } int value() { return this.x; } } int main() { var box = new Vessel(); return box.value(); }\n'),
		'field-initialize-twice': (False, 'class Vessel { private int x; init() { this.x = 1; this.x = 42; } int value() { return this.x; } } int main() { var box = new Vessel(); return box.value(); }\n'),
		'field-owner-initialize-twice': (False, 'class Vessel { private owned int[] x; init() { this.x = new int[1]; this.x = new int[42]; } int value() { return len(this.x); } } int main() { var box = new Vessel(); return box.value(); }\n'),
		'field-missing-init': (False, 'class Vessel { private owned int[] x; init() {} int value() { return len(this.x); } } int main() { var box = new Vessel(); return box.value(); }\n'),
		'field-replace-buffer': (True, 'class Vessel { private owned int[] x; init() { this.x = new int[1]; } void replace(owned int[] x) { this.x = move x; } int value() { return len(this.x); } } int main() { var box = new Vessel(); var x = new int[42]; box.replace(move x); return box.value(); }\n'),
		'field-move-buffer': (False, 'class Vessel { private owned int[] x; init() { this.x = new int[42]; } owned int[] take() { return move this.x; } } int main() { var box = new Vessel(); var x = box.take(); return len(x); }\n'),
		'field-copy-buffer': (False, 'class Vessel { private owned int[] x; init() { this.x = new int[42]; } owned int[] take() { return this.x; } } int main() { var box = new Vessel(); var x = box.take(); return len(x); }\n'),
		'field-readonly-mutate': (False, 'class Vessel { private readonly int x; init() { this.x = 1; } void change() { this.x = 42; } } int main() { var box = new Vessel(); box.change(); return 42; }\n'),
		'field-readonly-exchange': (False, 'class Vessel { private readonly owned int[] x; init() { this.x = new int[1]; } void change(owned int[] y) { swap(this.x, y); } } int main() { var box = new Vessel(); var y = new int[42]; box.change(move y); return 42; }\n'),
		'field-self-exchange': (True, 'class Vessel { private owned int[] x; init() { this.x = new int[42]; } void exchange() { swap(this.x, this.x); } int value() { return len(this.x); } } int main() { var box = new Vessel(); box.exchange(); return box.value(); }\n'),
		'field-alias-exchange': (True, 'class Vessel { private owned int[] x; init() { this.x = new int[42]; } void exchange(Vessel other) { swap(this.x, other.x); } int value() { return len(this.x); } } int main() { var box = new Vessel(); box.exchange(box); return box.value(); }\n'),
		'field-borrowed-owner': (False, 'class Vessel { private borrowed int[] x; init(int[] x) { this.x = x; } void change() { var y = new int[1]; swap(this.x, y); } } int main() { return 42; }\n'),
		'field-move-class': (False, 'class Item { init() {} } class Vessel { private owned Item item; init(owned Item item) { this.item = move item; } owned Item take() { return move this.item; } } int main() { var i = new Item(); var box = new Vessel(move i); var x = box.take(); return 42; }\n'),
		'field-replace-class': (True, 'class Item { init() {} } class Vessel { private owned Item item; init(owned Item item) { this.item = move item; } void replace(owned Item item) { this.item = move item; } } int main() { var i = new Item(); var box = new Vessel(move i); var x = new Item(); box.replace(move x); return 42; }\n'),
		'field-Class-direct-new': (False, 'class Item { init() {} } class Box { private owned Item item; init(owned Item item) { this.item = move item; } void replace() { this.item = new Item(); } } int main() { var item = new Item(); var box = new Box(move item); box.replace(); return 42; }\n'),
		'field-Class-direct-new-init': (False, 'class Item { init() {} } class Box { private owned Item item; init() { this.item = new Item(); } } int main() { var box = new Box(); return 42; }\n'),
		'field-Class-null': (False, 'class Item { init() {} } class Box { private owned Item item; init(owned Item item) { this.item = move item; } void replace() { this.item = null; } } int main() { var item = new Item(); var box = new Box(move item); box.replace(); return 42; }\n'),
		'discard-string': (True, 'string ignored() { return "kept"; } int main() { ignored(); return 42; }\n'),
	}
	inherited = load_module('r4_inherited_C0_policy', ROOT/'tests/selfhost-effects/recover-r3-policy.py')
	rows.update({'inherited-'+name:value for name, value in inherited.corpus().items()})
	return rows


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_policy_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-policy-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); rows = []; commands = []
	if a.component:
		identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	for name, (expected, source_text) in corpus().items():
		source = leaf/(name+'.astra'); source.write_text(source_text); exe = build/name
		def run(argv, suffix):
			argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'-'+suffix+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=120); (leaf/(name+'-'+suffix+'.stdout')).write_bytes(r.stdout); (leaf/(name+'-'+suffix+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name+'-'+suffix, argv=argv, exit=r.returncode, start=start, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
		r = run([C0, '-'+a.mode, source, ROOT/'lib/astra/base/errors.astra', '-o', exe], 'build'); assert r.returncode in (0, 1)
		legal = r.returncode == 0
		if expected is not None: assert legal == expected, (name, r.stderr)
		row = dict(name=name, source_sha256=sha(source), legal=legal, declared_expectation=expected, compiler_sha256=sha(C0))
		if legal:
			execution = run([exe], 'execute'); row.update(actual_exit=execution.returncode, ELF_sha256=sha(exe))
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], 'memory'); row['memory_exit'] = memory.returncode
			assert memory.returncode == execution.returncode and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
		if a.component:
			target = build/(name+'.ll'); target.write_text('R4 policy output sentinel\n'); before = sha(target); native = run([a.component, '--native', target, source, ROOT/'lib/astra/base/errors.astra'], 'Astra-emit')
			positive = name in ('discard-false', 'discard-scalar', 'discard-error', 'discard-string', 'field-mixed', 'field-exchange', 'field-replace-buffer', 'field-self-exchange', 'field-alias-exchange', 'field-replace-class', 'inherited-inferred-parenthesized-construction', 'inherited-discarded-checked-scalar-result')
			assert (native.returncode == 0) == positive, (name, native.stdout[-2000:], native.stderr[-2500:])
			row.update(Astra_exit=native.returncode, Astra_emitted=positive, first_output=native.stdout.decode(), component_sha256=sha(a.component))
			if positive:
				assert run(['opt', '-passes=verify', '-disable-output', target], 'Astra-verify').returncode == 0; obj = build/(name+'.o'); program = build/(name+'-Astra'); assert run(['llc', '-filetype=obj', '-'+a.mode, target, '-o', obj], 'Astra-object').returncode == 0; assert run(['cc', '-no-pie', obj, '-o', program], 'Astra-link').returncode == 0; assert run([program], 'Astra-execute').returncode == 42
				memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', program], 'Astra-memory'); assert memory.returncode == 42 and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
				row.update(Astra_ELF_sha256=sha(program), Astra_LLVM_sha256=sha(target))
			else: assert sha(target) == before
		rows.append(row); (leaf/'result.json').write_text(json.dumps(dict(status='C0_POLICY_OBSERVATIONS', profile=a.mode, programs=rows, Astra_native_credit=0), indent=2)+'\n'); print(name, 'legal' if legal else 'rejected', row.get('actual_exit'), flush=True)


if __name__ == '__main__':
	main()
