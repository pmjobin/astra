# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Check source rejection contracts through public stage boundaries."""
from pathlib import Path
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
PRELUDE = 'owned R empty() { return null; } owned Other wrong() { return null; } void use(borrowed R r) { id(r); }\n'
CLASS = 'class C { owned R r; init() { this.r = empty(); } void replace() { this.r = empty(); } }\n'
CASES = {
	'missing': ('class C { owned R r; init() {} }', 'not definitely initialized'),
	'duplicate': ('class C { owned R r; init() { this.r = empty(); this.r = empty(); } }', 'initialized twice'),
	'read-before-init': ('class C { owned R r; init() { use(this.r); this.r = empty(); } }', 'read before definite initialization'),
	'missing-branch': ('class C { owned R r; init(bool choose) { if (choose) { this.r = empty(); } } }', 'not definitely initialized'),
	'plain': ('class C { R r; }', 'resource-valued struct fields are unsupported'),
	'owned-class': ('class Child {} class C { owned Child child; init() {} }', 'not definitely initialized'),
	'owned-struct': ('struct Pair { int x; } class C { owned Pair pair; init() {} }', 'owned fields require an exact nominal Resource'),
	'owned-pointer': ('class C { owned void* r; init() {} }', 'owned fields require an exact nominal Resource'),
	'owned-typed-pointer': ('class C { owned int* r; init() {} }', 'owned fields require an exact nominal Resource'),
	'owned-scalar': ('class C { owned int r; init() {} }', 'owned fields require an exact nominal Resource'),
	'owned-vector': ('class C { owned f32<4> r; init() {} }', 'owned fields require an exact nominal Resource'),
	'generic-owner': ('struct S<T> { owned T r; }', 'owned struct fields are unsupported'),
	'plain-struct-resource': ('struct S { R r; }', 'resource-valued struct fields are unsupported'),
	'wrong-result': ('class C { owned R r; init() { this.r = wrong(); } }', 'exact Resource type'),
	'null-value': ('class C { owned R r; init() { this.r = null; } }', 'exact Resource type'),
	'move-out': (CLASS+'void f(borrowed C c) { owned R r = move c.r; }', 'moving ownership out of an owned field'),
	'release': (CLASS+'void f(borrowed C c) { release c.r; }', 'explicit release of an owned field'),
	'field-to-field': (CLASS+'void f(borrowed C a, borrowed C b) { a.r = move b.r; }', 'projected owner move requires a fresh named local destination'),
	'self-move': ('class C { owned R r; init() { this.r = move this.r; } }', 'moving ownership out of an owned field'),
	'deinit-move-out': ('class C { owned R r; init() { this.r = empty(); } deinit() { owned R r = move this.r; } }', 'moving ownership out of an owned field'),
	'deinit-release': ('class C { owned R r; init() { this.r = empty(); } deinit() { release this.r; } }', 'explicit release of an owned field'),
	'borrow-copy': (CLASS+'void f(borrowed C c) { R r = c.r; }', 'copying and escaping'),
	'borrow-return': (CLASS+'R f(borrowed C c) { return c.r; }', 'copying and escaping'),
	'borrow-overlap': (CLASS+'void mutate(borrowed C c, borrowed R r) { c.r = empty(); use(r); } void f(borrowed C c) { mutate(c, c.r); }', 'temporary owned-field borrow overlaps'),
	'borrow-later-argument': (CLASS+'int mutate(borrowed C c) { c.r = empty(); return 0; } void pair(borrowed R r, int n) {} void f(borrowed C c) { pair(c.r, mutate(c)); }', 'temporary owned-field borrow overlaps'),
	'borrow-method-receiver': ('class C { owned R r; init() { this.r = empty(); } void mutate(borrowed R r) { this.r = empty(); use(r); } void f() { this.mutate(this.r); } }', 'temporary owned-field borrow overlaps'),
	'moved-constructor-input': ('class C { owned R r; init(owned R r) { this.r = move r; use(r); } }', 'moved'),
	'moved-replacement-input': (CLASS+'void f(borrowed C c, owned R r) { c.r = move r; use(r); }', 'moved'),
}


def main(compiler, out):
	out.mkdir(parents=True, exist_ok=True)
	records = []
	for name, (source, message) in CASES.items():
		path = out/(name+'.astra'); path.write_text(PRELUDE+source+'\n')
		for stage in ['cfg', 'ssa', 'nabi', 'llvm']:
			result = subprocess.run([str(compiler), '--dump-'+stage, str(path), '--vapi', str(ROOT/'tests/own-field/fixtures/resources.vapi')], capture_output=True, text=True)
			assert result.returncode == 1 and message in result.stderr and not result.stdout, (name, stage, result)
			records.append(dict(name=name, stage=stage, diagnostic=result.stderr.strip()))
	(out/'results.json').write_text(json.dumps(records, indent='\t')+'\n')
	print(f'{len(records)} rejection checks')


if __name__ == '__main__':
	main(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
