#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Scalar bit-pattern and signature-derived generic buffer exchange oracles."""
import json
import os
import subprocess
import time
from state import RUNTIME, BUILD, C0, sha


def main():
	leaf = RUNTIME/'extras-v1'; leaf.mkdir(exist_ok=False); build = BUILD/'extras-oracles-v1'; build.mkdir(exist_ok=False)
	cases = {
		'floating-buffer-patterns': ('struct Stamp { int code; }\nint main() { Stamp s = {code = 33}; var a = new f64[1]; var b = new f64[2]; a[0] = -0.0; b[1] = 0.0 / 0.0; swap(a, b); if (len(a) != 2 || len(b) != 1 || !(a[1] != a[1]) || !(1.0 / b[0] < 0.0)) return 99; return s.code; }\n', 33),
		'generic-owning-bool-parameters': ('struct Stamp { int code; }\nowned T[] rotate<T>(owned T[] a, owned T[] b) { swap(a, b); return move a; }\nint main() { Stamp s = {code = 34}; var a = new bool[0]; var b = new bool[2]; b[1] = true; var result = rotate<bool>(move a, move b); if (len(result) != 2 || !result[1]) return 99; return s.code; }\n', 34),
	}
	selection = []; commands = []
	for name, (source, expected) in cases.items():
		path = leaf/(name+'.astra'); path.write_text(source); selection.append(dict(name=name, sources=[dict(path=str(path), sha256=sha(path), bytes=path.stat().st_size)], expected_exit=expected, oracle='Independent count/IEEE signed-zero/NaN or bool-element assertions and manual return value'))
		for mode in ('O0', 'O2'):
			target = build/(name+'-'+mode)
			for phase, argv, status in [('compile', [C0, '-'+mode, path, '-o', target], 0), ('execute', [target], expected)]:
				label = name+'-'+mode+'-'+phase; begin = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *map(str, argv)], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
				(leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=label, argv=list(map(str, argv)), exit=r.returncode, expected=status, start=begin, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == status and r.stdout == r.stderr == b'', (label,r.stderr)
	(leaf/'selection.json').write_text(json.dumps(selection, indent=2)+'\n'); print('IEEE buffer and generic bool owner-parameter C0/manual oracles pass at O0/O2')


if __name__ == '__main__':
	main()
