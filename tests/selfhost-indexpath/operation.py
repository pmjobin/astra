#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze a byte-exact source operation and disclose its separate CFG driver.

The complete original inspect body is independently C0-qualified, but its
native SSA construction exhausts the unchanged 8M budget. This narrower view
preserves the operation's exact bytes and spans; it does not qualify that body.
"""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, sha


def main():
	leaf = RUNTIME/'operation-v1'; leaf.mkdir(exist_ok=False)
	build = ROOT.parent/'codex/work/astra/build/indexpath18/operation-oracles'; build.mkdir(parents=True, exist_ok=True)
	original = ROOT/'compiler/cfg/consume.astra'; raw = original.read_bytes(); start, end = 650, 670
	assert sha(original) == 'f0e32ad005bc4a2d10244821bb84ab815c4aab7332654002066cd470382033c0' and raw[start:end] == b'd.functions[f].entry'
	view = bytearray(b if b in (10, 13) else 32 for b in raw)
	prefix = b'int cfg_original_entry(CfgData d, int f) { return '; suffix = b';\n}\n'
	view[start-len(prefix):start] = prefix; view[start:end] = raw[start:end]; view[end:end+len(suffix)] = suffix
	path = leaf/'original-operation-view.astra'; path.write_bytes(view); assert len(view) == len(raw) and view[start:end] == raw[start:end]
	provider = leaf/'provider.astra'; provider.write_text('''struct CfgFunction { int entry; int exit; }
struct CfgBlock { int function; int origin; int role; int instruction; int terminators; int term; int condition; int yes; int no; bool reachable; }
class CfgData {
	owned CfgFunction[] functions; owned CfgBlock[] blocks;
	int function_count; int block_count;
	init() { this.functions = new CfgFunction[2]; this.blocks = new CfgBlock[2]; this.function_count = 2; this.block_count = 2; }
}
''')
	entry = leaf/'main.astra'; entry.write_text('''int main() {
	var d = new CfgData(); CfgFunction one = {entry = 1, exit = 2}; CfgFunction two = {entry = 2, exit = 1}; d.functions[0] = one; d.functions[1] = two;
	CfgBlock a = {function = 1, origin = 0, role = 0, instruction = 0, terminators = 1, term = 1, condition = 0, yes = 2, no = 0, reachable = true};
	CfgBlock b = {function = 1, origin = 0, role = 0, instruction = 0, terminators = 1, term = 1, condition = 0, yes = 1, no = 0, reachable = true}; d.blocks[0] = a; d.blocks[1] = b;
	var seen = new int[d.block_count]; int f = 0; int reachable = 0; int edges = 0; int backedges = 0;
	while (f < d.function_count) {
		int at = cfg_original_entry(d, f);
		while (seen[at - 1] == 0) {
			seen[at - 1] = 1; reachable = reachable + 1; var block = d.blocks[at - 1];
			if (block.yes == 0) break;
			edges = edges + 1;
			if (seen[block.yes - 1] != 0) { backedges = backedges + 1; break; }
			at = block.yes;
		}
		f = f + 1;
	}
	if (reachable != 2 || edges != 2 || backedges != 1) return 90;
	return reachable * 10 + edges * 2 + backedges;
}
''')
	c0 = ROOT.parent/'codex/work/astra/build/llvm23-migration/production-final/astrac'; sources = [provider, path, entry]; commands = []
	def run(argv, name, expected=0):
		start_time = time.monotonic(); r = subprocess.run(list(map(str, argv)), cwd=build, capture_output=True, timeout=120, env=dict(os.environ, CCACHE_DISABLE='1'))
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode, monotonic_start=start_time, monotonic_end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == expected, (name, r.stderr); return r.stdout
	spec = importlib.util.spec_from_file_location('probe', ROOT/'tests/selfhost-classstorage/abi-probe.py'); probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)
	full = probe.syntax(run([c0, '--dump-syntax', original], 'original-syntax').decode()); bounded = probe.syntax(run([c0, '--dump-syntax', path], 'view-syntax').decode())
	def operations(node):
		rows = []
		if isinstance(node, list):
			if node[:1] == ['field-access'] and node[-1:] == ['entry']: rows.append(node)
			for child in node: rows += operations(child)
		return rows
	assert operations(full) == operations(bounded) and len(operations(full)) == 1
	for mode in ('O0', 'O2'):
		product = build/('original-index-operation-'+mode); run([c0, '-'+mode, *sources, '-o', product], 'C0-build-'+mode); run([product], 'C0-execute-'+mode, 25)
	row = dict(name='original-index-operation', expected_exit=25, sources=[dict(path=str(p), bytes=p.stat().st_size, sha256=sha(p)) for p in sources])
	(leaf/'selection.json').write_text(json.dumps([row], indent=2)+'\n')
	(leaf/'result.json').write_text(json.dumps(dict(status='C0_QUALIFIED_NATIVE_PENDING', original=dict(path=str(original), sha256=sha(original), operation_span=[start, end], operation=raw[start:end].decode()), view=dict(path=str(path), sha256=sha(path), bytes_preserved=[start, end], wrapper_prefix_span=[start-len(prefix), start], wrapper_suffix_span=[end, end+len(suffix)]), independent_C0_operation_AST_equal=True, C0_exit=25, expected_counters=dict(reachable=2, edges=2, backedges=1), driver='Separately authored finite outdegree-one CFG traversal. The exact original operation selects each function entry. CfgData is an explicit bounded harness with exact CfgFunction record fields; full original shared identity and unrelated fields are not admitted.', full_original_body='C0 O0/O2 qualified in frozen-v2; native SSA remains DEFERRED at unchanged 8000000 steps, as observed in pilot-v4-O0.'), indent=2)+'\n')
	print('Original operation AST/bytes/span preserved; independent CFG driver C0 O0/O2 exits 25')


if __name__ == '__main__':
	main()
