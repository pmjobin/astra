#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent negative sources with accepted twins and bad-object containment."""
import argparse
import json
import os
from pathlib import Path
import resource
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, read, sha
from corpus import BOX


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--name', required=True); p.add_argument('--oracle-only', action='store_true'); a = p.parse_args()
	leaf = RUNTIME/a.name; build = BUILD/a.name; leaf.mkdir(exist_ok=False); build.mkdir(exist_ok=False)
	cases = {
		'nominal-record': 'struct A { int x; } struct B { int x; } int main() { var a = new A[1]; var b = new B[1]; swap(a, b); return 0; }',
		'borrowed-left': 'int change(int[] view) { var b = new int[1]; swap(view, b); return 0; } int main() { var a = new int[1]; return change(a); }',
		'borrowed-right': 'int change(int[] view) { var a = new int[1]; swap(a, view); return 0; } int main() { var b = new int[1]; return change(b); }',
		'moved-left': 'int main() { var a = new int[1]; var b = new int[1]; var c = move a; swap(a, b); return len(c); }',
		'released-right': 'int main() { var a = new int[1]; var b = new int[1]; release b; swap(a, b); return 0; }',
		'live-dependent-view': 'int main() { var a = new int[1]; var b = new int[1]; int[] view = a; swap(a, b); return view[0]; }',
		'field-dependent-view': BOX+'int main() { var a = new Box(); var b = new int[1]; int[] view = a.data; swap(a.data, b); return view[0]; }',
		'aliased-field-loan': BOX+'int change(borrowed Box a, borrowed Box b) { int[] view = a.data; swap(b.data, b.other); return view[0]; } int main() { var a = new Box(); return change(a, a); }',
		'move-operand': 'int main() { var a = new int[1]; var b = new int[1]; swap(move a, b); return 0; }',
		'rvalue-operand': 'int main() { var b = new int[1]; swap(new int[1], b); return 0; }',
		'direct-class-owner': BOX+'int main() { var a = new Box(); var b = new Box(); swap(a, b); return 0; }',
		'wrong-element-owner': 'class Item {} int main() { var a = new Item[1]; var b = new Item[1]; swap(a, b); return 0; }',
		'readonly-field': 'class Readonly { readonly string data; init() { this.data = "x"; } } int main() { var a = new Readonly(); var b = new int[1]; swap(a.data, b); return 0; }',
		'generic-unmatched': 'void exchange<T, U>(owned T[] a, owned U[] b) { swap(a, b); } int main() { var a = new int[1]; var b = new int[1]; exchange<int, int>(move a, move b); return 0; }',
	}
	method_box = BOX.replace('\n}\n', '\n\tint rotate() { swap(this.data, this.other); return 0; }\n}\n')
	use = 'int use(int[] values, int n) { return n; } '
	cases.update({
		'pending-field-left': method_box+use+'int main() { var a = new Box(); return use(a.data, a.rotate()); }',
		'pending-field-right': method_box+use+'int main() { var a = new Box(); return use(a.other, a.rotate()); }',
		'pending-containing-alias': method_box+use+'int change(borrowed Box a, borrowed Box b) { return use(a.data, b.rotate()); } int main() { var a = new Box(); return change(a, a); }',
		'pending-indexed-destination': method_box+'int main() { var a = new Box(); a.data[0] = a.rotate(); return 0; }',
		'destructive-right-receiver': BOX+'owned Box identity(owned Box box) { return move box; } int main() { var a = new Box(); swap(a.data, identity(move a).data); return 0; }',
		'destructive-left-receiver': BOX+'owned Box identity(owned Box box) { return move box; } int main() { var a = new Box(); swap(identity(move a).data, a.data); return 0; }',
		'indexed-element-target': 'int main() { var a = new int[1]; var b = new int[1]; swap(a[0], b); return 0; }',
		'fixed-array-target': 'int main() { int[2] a = {1, 2}; var b = new int[2]; swap(a, b); return 0; }',
		'property-target': 'class Property { owned int[] data; init() { this.data = new int[1]; } property int size { get { return len(this.data); } } } int main() { var a = new Property(); var b = new int[1]; swap(a.size, b); return 0; }',
		'pending-own-argument': BOX.replace('\n}\n', '\n\tint first(int[] values) { return values[0]; }\n}\n')+'int main() { var box = new Box(); return box.first(box.data); }',
		'partly-initialized-field': 'class Partial { owned int[] a; owned int[] b; init() { this.a = new int[1]; swap(this.a, this.b); this.b = new int[1]; } } int main() { var p = new Partial(); return 0; }',
	})
	commands = []; rows = []
	def run(argv, name):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *map(str, argv)], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=180)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, start=start, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	valid = next(row for row in read(RUNTIME/'corpus-v1/selection.json') if row['name'] == 'local-field')
	output = build/'preserved.o'
	if a.oracle_only:
		r = run([C0, '-'+a.mode, '--entry-object', *[s['path'] for s in valid['sources']], '-o', output], 'valid-twin-C0'); assert r.returncode == 0
	else:
		r = run([a.component, '--classstorage-emit-obj', a.mode, output, *[s['path'] for s in valid['sources']]], 'valid-twin'); assert r.returncode == 0
	original = sha(output)
	for name, source in cases.items():
		path = leaf/(name+'.astra'); path.write_text(source+'\n')
		c = run([C0, '--check', path], name+'-C0'); n = None
		if not a.oracle_only:
			n = run([a.component, '--classstorage-emit-obj', a.mode, output, path], name+'-native'); assert n.returncode != 0 and sha(output) == original, name
		rows.append(dict(name=name, source_sha256=sha(path), C0_status=c.returncode, native_status=n.returncode if n else None, C0_diagnostic=c.stderr.decode(), native_diagnostic=n.stderr.decode() if n else None, classification='C0_REJECTED' if c.returncode else 'C0_ADMITTED_NATIVE_DEFERRED', twin=valid['name'], destination_sha256=original))
		(leaf/'observations.json').write_text(json.dumps(rows, indent=2)+'\n'); print(name, c.returncode, n.returncode if n else 'ORACLE_ONLY', flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='ORACLE_ONLY' if a.oracle_only else 'PASS', component_sha256=sha(a.component), mode=a.mode, observations=rows, limitation='Every native refusal is recorded with its actual stage/diagnostic. C0 parser or unrelated unsupported-domain failures do not establish an owner-flow proof.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
