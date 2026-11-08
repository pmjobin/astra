#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C0/source-stage refusals for illegal unary domains."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

CASES = {
	'not-int': 'int main() { int value = 1; if (!value) return 42; return 3; }',
	'negative-u32': 'u32 bad(u32 value) { return -value; } int main() { return 42; }',
	'plus-bool': 'bool bad(bool value) { return +value; } int main() { return 42; }',
	'complement-bool': 'bool bad(bool value) { return ~value; } int main() { return 42; }',
	'not-float': 'bool bad(f32 value) { return !value; } int main() { return 42; }',
	'complement-float': 'f64 bad(f64 value) { return ~value; } int main() { return 42; }',
	'negative-u64': 'u64 bad(u64 value) { return -value; } int main() { return 42; }',
	'complement-text': 'string bad(string value) { return ~value; } int main() { return 42; }',
	'not-buffer': 'bool bad(int[] value) { return !value; } int main() { return 42; }',
	'not-void': 'void empty() {} int main() { if (!empty()) return 42; return 3; }',
	'complement-Class': 'class Item { init() {} } int main() { var value = new Item(); var bad = ~value; return 42; }',
	'negative-pointer': 'int main() { void* value = null; var bad = -value; return 42; }',
}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r5_prefix_negative_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('prefix-negative-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	if a.component:
		identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, name):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	for name, text in CASES.items():
		source = leaf/(name+'.astra'); source.write_text(text+'\n'); c0 = run([C0, '-'+a.mode, source, ROOT/'lib/astra/base/errors.astra', '-o', build/name], name+'-C0'); assert c0.returncode == 1 and b'error:' in c0.stderr
		row = dict(name=name, source_sha256=sha(source), C0_rejected=True)
		if a.component:
			target = build/(name+'.ll'); target.write_text('Unary source rejection sentinel\n'); before = sha(target); native = run([a.component, '--native', target, source, ROOT/'lib/astra/base/errors.astra'], name+'-Astra'); assert native.returncode == 4 and sha(target) == before; row.update(Astra_Typecore_rejected=True, destination_preserved=True)
		rows.append(row); (leaf/'result.json').write_text(json.dumps(dict(status='UNARY_SOURCE_NEGATIVES', profile=a.mode, programs=rows, component_sha256=sha(a.component) if a.component else None, Astra_native_credit=0, limitation='Twelve illegal source domains, independently refused by C0 and, when supplied, Astra Typecore. These are source negative controls, not twelve new stage mutation categories or native executions.'), indent=2)+'\n')
	print(a.mode, len(rows), 'illegal source unary forms refused', flush=True)


if __name__ == '__main__':
	main()
