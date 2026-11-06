#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Disjoint source controls for conditional typing and fail-closed effects."""
import argparse
import json
from pathlib import Path
import subprocess
import time
from state import bounded_run, ROOT, RUNTIME, BUILD, C0, sha, read
from observe import parse

CLASSES = 'class Parcel { init() {} }\nclass Ripple { init() {} }\n'
FACTORY = 'owned Parcel produce() throws Error { var result = new Parcel(); return move result; }\n'


def main():
	p = argparse.ArgumentParser(); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); p.add_argument('--full-cli', action='store_true'); p.add_argument('--mode', choices=('O0', 'O2'), default='O0'); a = p.parse_args()
	leaf = RUNTIME/('controls-'+a.version); leaf.mkdir(exist_ok=False)
	build = BUILD/('controls-'+a.version); build.mkdir(exist_ok=False)
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	cases = {
		'parcel': (CLASSES+FACTORY+'void take(owned Parcel value) {}\nvoid relay() throws Error { var parcel = produce(); take(move parcel); }\nint main() { return 42; }\n', 0, 0, True),
		'ripple': (CLASSES+'owned Ripple manufacture() throws Error { var result = new Ripple(); return move result; }\nvoid receive(owned Ripple value) {}\nvoid relay() throws Error { var pulse = manufacture(); receive(move pulse); }\nint main() { return 42; }\n', 0, 0, True),
		'generic-container': (CLASSES+FACTORY+'void relay() throws Error { var bag = new Bag<Parcel>(); var parcel = produce(); bag.append(move parcel); }\nint main() { return 42; }\n', 0, 0, True),
		'mismatched-nominal': (CLASSES+FACTORY+'void take(owned Ripple value) {}\nvoid relay() throws Error { var parcel = produce(); take(move parcel); }\nint main() { return 42; }\n', 1, 1, False),
		'unknown-result': (CLASSES+'owned Missing produce() throws Error { return null; }\nvoid relay() throws Error { var parcel = produce(); }\nint main() { return 42; }\n', 1, 1, False),
		'unhandled-effect': (CLASSES+FACTORY+'void relay() { var parcel = produce(); }\nint main() { return 42; }\n', 1, 0, True),
		'nonthrowing': (CLASSES+'owned Parcel produce() { var result = new Parcel(); return move result; }\nvoid take(owned Parcel value) {}\nint main() { var parcel = produce(); take(move parcel); return 42; }\n', 0, 0, False),
		'borrowed-move': (CLASSES+FACTORY+'void take(owned Parcel value) {}\nvoid relay(borrowed Parcel parcel) throws Error { take(move parcel); }\nint main() { return 42; }\n', 1, 0, False),
	}
	results = []; commands = []
	for name, (source, c0_exit, failed, pending) in cases.items():
		path = leaf/(name+'.astra'); path.write_text(source)
		inputs = [path, ROOT/'lib/astra/base/errors.astra']
		if name == 'generic-container': inputs.append(ROOT/'lib/astra/collections/bag.astra')
		row = dict(name=name, sources=[dict(path=str(s), sha256=sha(s)) for s in inputs], C0_expected=c0_exit)
		prefix = ['--effects-trace', a.mode, str(build/'unused')] if a.full_cli else []
		for label, argv in [('C0', [C0, '--check', *inputs]), ('observer', [a.component, *prefix, *inputs])]:
			start = time.monotonic(); r = bounded_run(list(map(str, argv)), cwd=build, capture_output=True, timeout=240)
			(leaf/(name+'-'+label+'.stdout')).write_bytes(r.stdout); (leaf/(name+'-'+label+'.stderr')).write_bytes(r.stderr)
			commands.append(dict(name=name+'-'+label, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start, stdout_sha256=sha(leaf/(name+'-'+label+'.stdout')), stderr_sha256=sha(leaf/(name+'-'+label+'.stderr'))))
			(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
			assert r.returncode == (c0_exit if label == 'C0' else 0), r.stderr[-3000:]
			if label == 'observer':
				tables = parse(leaf/(name+'-'+label+'.stdout'))
				assert int(tables['CHECKED_STATE'][0][0]) == failed, (name, tables['CHECKED_STATE'])
				assert int(tables['STATUS'][0][0]) != 0, 'No source with an unsupported effect/root may be admitted'
				if pending:
					initializers = [x for x in tables['INITIALIZER'] if int(x[3]) == 17 and int(x[1]) > 0]
					assert initializers and all(int(x[2]) & 4 for x in initializers)
					assert any(int(x[1]) > 0 and int(x[2]) & 4 and int(x[3]) == 19 for x in tables.get('MOVE', [])) or name == 'unhandled-effect'
				row.update(checked_state=tables['CHECKED_STATE'], conditional_initializers=tables.get('INITIALIZER', []), locals=tables.get('LOCAL', []), moves=tables.get('MOVE', []), Flow_status=tables['STATUS'], deferrals=tables.get('DEFER', []), limitation='Static type/effect split only; no owner/effect discharge or executable effects')
		results.append(row); (leaf/'result.json').write_text(json.dumps(dict(status='STATIC_CONTROLS_ONLY', component_sha256=sha(a.component), programs=results), indent=2)+'\n')
		print(name, 'C0', c0_exit, 'checked failed', failed, 'Flow remains closed', flush=True)


if __name__ == '__main__':
	main()
