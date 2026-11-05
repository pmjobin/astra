#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent equal-owner and concrete generic-record controls, after intake."""
import argparse
import json
import os
import subprocess
import time
from state import ROOT, RUNTIME, sha
from corpus import STORE


def main():
	p = argparse.ArgumentParser(); p.add_argument('--growth', action='store_true'); p.add_argument('--name', default='supplemental-v1'); a = p.parse_args()
	assert '/' not in a.name and a.name.startswith('supplemental-')
	leaf = RUNTIME/a.name; leaf.mkdir(exist_ok=False)
	build = ROOT.parent/'codex/work/astra/build/indexpath18'/a.name; build.mkdir(parents=True, exist_ok=True)
	c0 = ROOT.parent/'codex/work/astra/build/llvm23-migration/production-final/astrac'; commands = []; rows = []
	cases = [
		('two-owners', STORE, '''int main() { var a = new Store(1); var b = new Store(2); Row first = {tag = true, weight = 1.5, code = 17}; Row second = {tag = false, weight = 2.5, code = 53}; a.items[0] = first; b.items[1] = second; return a.items[0].code + b.items[1].code; }''', 70),
		('generic-record-array', '''struct Parcel<T> { bool tag; T value; }
class Depot { owned Parcel<int>[] records; init(int n) { this.records = new Parcel<int>[n]; } }
''', '''int main() { var d = new Depot(2); Parcel<int> p = {tag = true, value = 47}; d.records[1] = p; if (!d.records[1].tag) return 90; return d.records[1].value; }''', 47),
	]
	if a.growth:
		cases = [('grown-copy-transfer', '''struct Row { bool tag; f64 weight; int code; }
class Store { owned Row[] items; init(owned Row[] rows) { this.items = move rows; } }
''', '''int main() {
	var small = new Row[1]; Row first = {tag = true, weight = 1.5, code = 17}; small[0] = first;
	var grown = new Row[3]; grown[0] = small[0]; Row last = {tag = false, weight = 7.5, code = 37}; grown[2] = last;
	var s = new Store(move grown); if (len(s.items) != 3 || len(small) != 1 || small[0].code != 17 || s.items[0].weight != 1.5 || s.items[2].weight != 7.5) return 90;
	return s.items[0].code + s.items[2].code + len(s.items);
}''', 57)]
	for name, provider, entry, expected in cases:
		case = leaf/name; case.mkdir(); sources = [case/'provider.astra', case/'main.astra']; sources[0].write_text(provider); sources[1].write_text(entry+'\n')
		for mode in ('O0', 'O2'):
			product = build/(name+'-'+mode)
			for suffix, argv, exit in [('build', [c0, '-'+mode, *sources, '-o', product], 0), ('execute', [product], expected)]:
				start = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=build, capture_output=True, timeout=120, env=dict(os.environ, CCACHE_DISABLE='1'))
				label = name+'-'+mode+'-'+suffix; (leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr)
				commands.append(dict(name=label, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == exit, (label, r.stderr)
		rows.append(dict(name=name, expected_exit=expected, sources=[dict(path=str(p), bytes=p.stat().st_size, sha256=sha(p)) for p in sources]))
		(leaf/'selection.json').write_text(json.dumps(rows, indent=2)+'\n'); print(name, 'C0 O0/O2 qualified', flush=True)


if __name__ == '__main__':
	main()
