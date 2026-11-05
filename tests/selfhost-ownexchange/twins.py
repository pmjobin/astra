#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Accepted call/borrow twins for the conservative pending-field-loan rule."""
import json
import os
import subprocess
import time
from state import RUNTIME, BUILD, C0, sha
from corpus import BOX


def main():
	leaf = RUNTIME/'twins-v2'; leaf.mkdir(exist_ok=False); build = BUILD/'twins-oracles-v2'; build.mkdir(exist_ok=False)
	cases = {
		'completed-call-before-exchange': (BOX.replace('\n}\n', '\n\tint rotate() { swap(this.data, this.other); return len(this.data); }\n}\n')+'int first(int[] values) { return values[0]; } int main() { var box = new Box(); box.data[0] = 61; int result = first(box.data); int count = box.rotate(); if (result != 61 || count != 3 || box.other[0] != 61) return 99; return 31; }\n', 31),
		'snapshot-before-member-exchange': (BOX.replace('\n}\n', '\n\tint rotate() { swap(this.data, this.other); return len(this.data); }\n}\n')+'int main() { var box = new Box(); box.data[0] = 62; int snapshot = box.data[0]; int count = box.rotate(); if (snapshot != 62 || count != 3 || box.other[0] != 62) return 99; return 32; }\n', 32),
	}
	selection = []; commands = []
	for name, (source, expected) in cases.items():
		path = leaf/(name+'.astra'); path.write_text(source); selection.append(dict(name=name, sources=[dict(path=str(path), sha256=sha(path), bytes=path.stat().st_size)], expected_exit=expected, oracle='Independent saved value/count assertions; own receiver borrow is not a payload loan'))
		for mode in ('O0', 'O2'):
			target = build/(name+'-'+mode)
			for phase, argv, status in [('compile', [C0, '-'+mode, path, '-o', target], 0), ('execute', [target], expected)]:
				label = name+'-'+mode+'-'+phase; begin = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *map(str, argv)], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
				(leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=label, argv=list(map(str, argv)), exit=r.returncode, expected=status, start=begin, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == status and r.stdout == r.stderr == b'', (label,r.stderr)
	(leaf/'selection.json').write_text(json.dumps(selection, indent=2)+'\n'); print('Two accepted C0/manual call/borrow twins at O0/O2')


if __name__ == '__main__':
	main()
