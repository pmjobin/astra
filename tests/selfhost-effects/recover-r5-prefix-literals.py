#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Disclose C0-valid signed literal forms whose operand Typecore fact is absent."""
import argparse
import json
import os
from pathlib import Path
import time
from state import ROOT, C0, load_module, read, sha, bounded_run

CASES = {
	'negative-literal': 'int main() { int value = -42; return -value; }\n',
	'min-literal': 'int identity(int value) { return +value; } int main() { if (identity(-2147483648) == 0 - 2147483647 - 1) return 42; return 3; }\n',
	'small-min-literal': 'i8 inverse(i8 value) { return -value; } int main() { i8 value = -128; if (inverse(value) == value) return 42; return 3; }\n',
}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r5_literal_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('prefix-literals-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=240)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stderr[-2000:]); return r
	for name, text in CASES.items():
		source = leaf/(name+'.astra'); source.write_text(text); inputs = [source, ROOT/'lib/astra/base/errors.astra']; c0 = build/name; run([C0, '-'+a.mode, *inputs, '-o', c0], name+'-C0-build'); run([c0], name+'-C0-execute', (42,)); target = build/(name+'.ll'); target.write_text('Unqualified signed literal sentinel\n'); before = sha(target); native = run([a.component, '--native', target, *inputs], name+'-Astra', range(1, 9)); assert sha(target) == before
		ledger = run([a.component, '--classstorage-source-ledger', a.mode, build/'unused', *inputs], name+'-source-ledger', range(9)); nodes = []
		for line in ledger.stdout.splitlines():
			r = line.split()
			if r and r[0] == b'NODE' and bytes.fromhex(r[7].decode()).decode() == str(source): nodes.append(dict(node=int(r[1]), kind=int(r[2]), type=int(r[4]), flags=int(r[5]), deferred=int(r[6]), start=int(r[8]), end=int(r[9])))
		rows.append(dict(name=name, source_sha256=sha(source), C0_exit=42, C0_ELF_sha256=sha(c0), Astra_emitted=False, Astra_exit=native.returncode, stdout=native.stdout.decode(), destination_preserved=True, source_nodes=nodes))
	(leaf/'result.json').write_text(json.dumps(dict(status='C0_VALID_SIGNED_LITERAL_FORMS_UNQUALIFIED', profile=a.mode, component_sha256=sha(a.component), programs=rows, Astra_native_credit=0, limitation='The new integral unary lowering consumes exact typed operands. Typecore special-cases a signed integer literal at its prefix but leaves the magnitude operand without a recorded type; the independent RecoverFlow consumer refuses that absent fact. No type/owner proof is fabricated. Dynamic typed integer operands are qualified separately. These literal forms remain unfinished and have no Astra execution credit.'), indent=2)+'\n'); print(a.mode, 'three C0-valid signed literal forms remain explicitly unqualified', flush=True)


if __name__ == '__main__':
	main()
