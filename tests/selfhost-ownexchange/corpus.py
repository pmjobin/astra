#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent source/manual oracles, including a disclosed byte-preserving view."""
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, sha

RECORD = 'struct Stamp { int code; }\n'
BOX = '''class Box {
	owned int[] data;
	owned int[] other;
	init() { this.data = new int[2]; this.other = new int[3]; }
}
'''


def main():
	leaf = RUNTIME/'corpus-v1'; leaf.mkdir(parents=True, exist_ok=False)
	build = BUILD/'oracles-v1'; build.mkdir(parents=True, exist_ok=False)
	cases = {
		'local-unequal': (RECORD+'int main() { Stamp s = {code = 11}; var a = new int[2]; var b = new int[3]; a[0] = 17; b[0] = 29; swap(a, b); if (len(a) != 3 || len(b) != 2 || a[0] != 29 || b[0] != 17) return 99; return s.code; }\n', 11),
		'empty-live': (RECORD+'int main() { Stamp s = {code = 12}; var a = new int[0]; var b = new int[0]; swap(a, b); swap(a, a); if (len(a) != 0 || len(b) != 0) return 99; return s.code; }\n', 12),
		'one-empty-rearm': (RECORD+'int main() { Stamp s = {code = 13}; var a = new int[0]; var b = new int[4]; b[3] = 51; swap(a, b); var c = move a; a = new int[1]; a[0] = 7; if (len(b) != 0 || len(c) != 4 || c[3] != 51 || a[0] != 7) return 99; return s.code; }\n', 13),
		'local-field': (BOX+'int main() { var box = new Box(); var grown = new int[7]; grown[0] = 31; box.data[0] = 8; swap(box.data, grown); if (len(box.data) != 7 || len(grown) != 2 || box.data[0] != 31 || grown[0] != 8) return 99; return 14; }\n', 14),
		'field-local-reversed': (BOX+'int main() { var box = new Box(); var grown = new int[6]; grown[5] = 32; box.other[2] = 9; swap(grown, box.other); if (len(box.other) != 6 || len(grown) != 3 || box.other[5] != 32 || grown[2] != 9) return 99; return 15; }\n', 15),
		'two-fields': (BOX+'int main() { var a = new Box(); var b = new Box(); a.data[0] = 41; b.other[2] = 52; swap(a.data, b.other); if (len(a.data) != 3 || len(b.other) != 2 || a.data[2] != 52 || b.other[0] != 41) return 99; return 16; }\n', 16),
		'same-receiver': (BOX+'int main() { var a = new Box(); a.data[0] = 43; a.other[1] = 54; swap(a.data, a.other); if (len(a.data) != 3 || len(a.other) != 2 || a.data[1] != 54 || a.other[0] != 43) return 99; return 17; }\n', 17),
		'alias-receivers': (BOX+'int exchange(borrowed Box a, borrowed Box b) { swap(a.data, b.data); return len(a.data); }\nint main() { var a = new Box(); a.data[0] = 44; int count = exchange(a, a); if (count != 2 || a.data[0] != 44) return 99; return 18; }\n', 18),
		'field-self': (BOX+'int main() { var a = new Box(); a.data[0] = 45; swap(a.data, a.data); if (len(a.data) != 2 || a.data[0] != 45) return 99; return 19; }\n', 19),
		'early-loop': (BOX+'int work(borrowed Box box, int n) { var temp = new int[5]; int i = 0; while (i < n) { swap(box.data, temp); if (i == 2) return len(box.data); i = i + 1; } return len(temp); }\nint main() { var a = new Box(); int n = work(a, 4); if (n != 5 || len(a.data) != 5) return 99; return 20; }\n', 20),
		'record-growth': ('''struct Row { i64 weight; int tag; }
class Rows {
	owned Row[] data;
	init() { this.data = new Row[1]; }
	void grow() { var grown = new Row[5]; grown[0] = this.data[0]; swap(this.data, grown); }
}
int main() { var rows = new Rows(); Row r = {weight = 1234567, tag = 9}; rows.data[0] = r; rows.grow(); if (len(rows.data) != 5 || rows.data[0].weight != 1234567 || rows.data[0].tag != 9) return 99; return 21; }
''', 21),
		'generic-record': ('''struct Point { int x; int y; }
class Store<T> {
	owned T[] data;
	init() { this.data = new T[1]; }
	void grow() { var grown = new T[4]; grown[0] = this.data[0]; swap(this.data, grown); }
}
int main() { var box = new Store<Point>(); Point p = {x = 8, y = 13}; box.data[0] = p; box.grow(); if (len(box.data) != 4 || box.data[0].x != 8 || box.data[0].y != 13) return 99; return 22; }
''', 22),
		'owner-parameter': (RECORD+'''owned int[] rotate(owned int[] a, owned int[] b) { swap(a, b); return move a; }
int main() { Stamp s = {code = 23}; var a = new int[1]; var b = new int[8]; b[7] = 67; var result = rotate(move a, move b); if (len(result) != 8 || result[7] != 67) return 99; return s.code; }
''', 23),
	}
	selection = []
	for name, (source, expected) in cases.items():
		path = leaf/(name+'.astra'); path.write_text(source)
		selection.append(dict(name=name, sources=[dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path))], expected_exit=expected, oracle='Independent explicit count/element assertions and manual return value'))
	original = ROOT/'compiler/semantic/flow-model.astra'; raw = original.read_bytes()
	assert sha(original) == '4f901a3f358e7a5ccb7683938559ee8592f97c734d93a6a82b198586709c6f52'
	view = bytearray(b if b == 10 else 32 for b in raw)
	for begin, end in [(raw.index(b'struct FlowEvent {'), raw.index(b'\nstruct FlowLoan {')), (raw.index(b'\tbool room('), raw.index(b'\n\tint region('))]: view[begin:end] = raw[begin:end]
	start = raw.index(b'class FlowGraph {'); prefix = b'class FlowGraph {\n\towned FlowEvent[] events;\n\tint count;\n\tint limit;\n\tbool exhausted;\n\tinit() { this.events = new FlowEvent[1]; this.count = 0; this.limit = 100; this.exhausted = false; }\n'
	view[start:start+len(prefix)] = prefix
	end = raw.index(b'\n\tint region('); view[end:end+2] = b'\n}'
	path = leaf/'original-FlowGraph-view.astra'; path.write_bytes(view)
	assert view[3589:3614] == raw[3589:3614]
	provider = leaf/'flow-provider.astra'
	provider.write_text('''struct SyntaxSourceId { int index; }
struct SyntaxNodeId { int index; }
struct SyntaxSpan { SyntaxSourceId source; int start; int end; }
int syntax_grown_capacity(int capacity, int needed) { int result = capacity * 2; if (result < needed) result = needed; return result; }
''')
	entry = leaf/'flow-main.astra'; entry.write_text('''int main() {
	var graph = new FlowGraph(); int i = 0;
	while (i < 33) {
		FlowEvent row = {operation = 7, node = {index = 0}, span = {source = {index = 0}, start = 0, end = 0}, slot = 5, loan = 0, region = 0, call = 0, next = 0, other = 0, loop_head = 0, input = 0, output = 0, null_kind = 0, field = 0, source_field = 0, producer = {index = 0}, predicate = {index = 0}, required = false};
		int count = graph.add(row); if (count != i + 1) return 98; i = i + 1;
	}
	if (graph.count != 33 || len(graph.events) != 64 || graph.events[0].operation != 7 || graph.events[32].slot != 5) return 99;
	return 24;
}
''')
	selection.append(dict(name='original-FlowGraph-add', sources=[dict(path=str(p), bytes=p.stat().st_size, sha256=sha(p)) for p in (provider, path, entry)], expected_exit=24, oracle='33 appended rows; capacities 1,2,4,8,16,32,64; retained record values; unchanged complete add body', view=dict(original_sha256=sha(original), operation_span=[3589,3614], original_add_span=[raw.index(b'\tint add('), end], difference='Other methods/fields blanked; bounded constructor and storage fields; nominal syntax ID/Span dependencies and capacity helper disclosed separately. Whole FlowGraph remains unqualified.')))
	(leaf/'selection.json').write_text(json.dumps(selection, indent=2)+'\n')
	commands = []
	for mode in ('O0', 'O2'):
		for row in selection:
			target = build/(row['name']+'-'+mode)
			for label, argv, expected in [('build', [C0, '-'+mode, *[p['path'] for p in row['sources']], '-o', target], 0), ('execute', [target], row['expected_exit'])]:
				start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(row['name']+'-'+mode+'-'+label+'.time'), *map(str, argv)], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
				name = row['name']+'-'+mode+'-'+label; (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
				commands.append(dict(name=name, argv=list(map(str, argv)), expected=expected, exit=r.returncode, start=start, end=time.monotonic()))
				(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
				assert r.returncode == expected, (name, r.stderr.decode())
			print(mode, row['name'], 'C0/manual PASS', flush=True)


if __name__ == '__main__':
	main()
