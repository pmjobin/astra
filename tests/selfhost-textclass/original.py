#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind an exact original Class declaration view to its complete C0 module.

The view preserves byte offsets and the selected declaration verbatim. It does
not qualify the excluded factory or exception declarations for native lowering.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
	p = argparse.ArgumentParser()
	for name in ('compiler', 'runtime', 'build'): p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args()
	assert all(not path.resolve().is_relative_to(ROOT) for path in (a.runtime, a.build))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	assert sha(a.compiler) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	original = ROOT/'lib/astra/text/utf8-message.astra'; original_sha = sha(original)
	assert original_sha == 'd4c376e38317e1c4d32bf7c3f2956d8fa4b3586522151f19318b9481f1facd25'
	ledger_path = ROOT.parent/'codex/work/astra/runtime/genclass16/ledger-final-live-committed/ledger.json'
	ledger = json.loads(ledger_path.read_text())
	declarations = [row for row in ledger['declarations'].values() if row['path'] == str(original) and row['kind'] == 4 and row['name'] == 'Utf8Message']; assert len(declarations) == 1
	declaration = declarations[0]; start, end = declaration['start'], declaration['end']; raw = original.read_bytes()
	view = a.runtime/'original-declaration-view.astra'; view.write_bytes(bytes(byte if start <= i < end or byte in (10, 13) else 32 for i, byte in enumerate(raw)))
	assert view.read_bytes()[start:end] == raw[start:end] and len(view.read_bytes()) == len(raw)
	entry = a.runtime/'main.astra'
	entry.write_text('''int main() {
	var bag = new Bag<Utf8Message>(); bool room = bag.reserve(2);
	var first = new Utf8Message("a\\0é"); var second = new Utf8Message(first.text);
	if (first == second || first.text != second.text) return 90;
	bag.append(move first); bag.append(move second); bool grown = bag.reserve(5);
	var replacement = new Utf8Message("🙂"); bag.replace(0, move replacement);
	var a = bag.take(0); var b = bag.take(0);
	if (a.text != "🙂" || b.text != "a\\0é") return 91;
	return a.text.byte_length + b.text.byte_length + bag.count();
}
''')
	spec = importlib.util.spec_from_file_location('probe', ROOT/'tests/selfhost-classstorage/abi-probe.py'); probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)
	commands = []
	def run(argv, name, expected=0):
		start_time = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', a.runtime/(name+'.time'), *map(str, argv)], cwd=a.build, capture_output=True, timeout=120, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, seconds=time.monotonic()-start_time))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == expected, (name, r.stderr[-1500:])
		return r.stdout
	full_syntax = probe.syntax(run([a.compiler, '--dump-syntax', original], 'full-module-syntax').decode())
	view_syntax = probe.syntax(run([a.compiler, '--dump-syntax', view], 'selected-declaration-syntax').decode())
	assert view_syntax == [full_syntax[0], next(row for row in full_syntax[1:] if row[:2] == ['class', 'Utf8Message'])]
	bag = ROOT/'lib/astra/collections/bag.astra'; errors = ROOT/'lib/astra/base/errors.astra'; c0 = {}
	for mode in ('O0', 'O2'):
		product = a.build/('original-full-C0-'+mode)
		run([a.compiler, '-'+mode, errors, original, bag, entry, '-o', product], 'full-C0-'+mode)
		run([product], 'full-C0-execute-'+mode, 8); c0[mode] = dict(product_sha256=sha(product), exit=8)
		product = a.build/('original-view-C0-'+mode)
		run([a.compiler, '-'+mode, view, bag, entry, '-o', product], 'view-C0-'+mode); run([product], 'view-C0-execute-'+mode, 8)
	assert sha(original) == original_sha
	row = dict(name='original-Utf8Message', expected_exit=8, sources=[dict(path=str(path), bytes=path.stat().st_size, sha256=sha(path)) for path in (bag, view, entry)])
	(a.runtime/'selection.json').write_text(json.dumps([row], indent=2)+'\n')
	(a.runtime/'result.json').write_text(json.dumps(dict(status='C0_QUALIFIED_NATIVE_PENDING', original=dict(path=str(original), sha256=original_sha, declaration=declaration), source_ledger_sha256=sha(ledger_path), view=dict(path=str(view), sha256=sha(view), bytes_outside_selected_declaration='whitespace preserving every byte offset and newline'), C0=c0, identical_C0_declaration_AST=True, excluded_operations='Utf8MessageFactory, InvalidUtf8/Error and recoverable text operations remain DEFERRED for native lowering; no whole-module or Stage 1 claim.'), indent=2)+'\n')
	print('Original complete C0 module and byte-exact selected declaration agree at O0/O2; native evidence remains separate')


if __name__ == '__main__':
	main()
