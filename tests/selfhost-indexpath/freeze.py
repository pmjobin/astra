#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze independent C0 oracles and a byte-preserving original operation view."""
import os
from pathlib import Path
import subprocess
import time
import json
from corpus import CASES, NEGATIVES
from state import ROOT, RUNTIME, sha


def main():
	leaf = RUNTIME/'frozen-v2'; leaf.mkdir(exist_ok=False)
	build = ROOT.parent/'codex/work/astra/build/indexpath18/oracles'; build.mkdir(parents=True, exist_ok=True)
	c0 = ROOT.parent/'codex/work/astra/build/llvm23-migration/production-final/astrac'
	assert sha(c0) == 'e3b2a5d6a4b9c5a42becbc3704f2d062489fb6f99a5ed1727461dfef4cf8681b'
	commands = []
	def run(args, name, expected=0):
		start = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *map(str, args)], cwd=build, capture_output=True, timeout=120, env=dict(os.environ, CCACHE_DISABLE='1'))
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(argv=list(map(str, args)), name=name, exit=r.returncode, monotonic_start=start, monotonic_end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		if expected is not None: assert r.returncode == expected, (name, r.returncode, r.stderr[-2000:])
		return r
	items = []
	original = ROOT/'compiler/cfg/consume.astra'; raw = original.read_bytes(); assert sha(original) == 'f0e32ad005bc4a2d10244821bb84ab815c4aab7332654002066cd470382033c0'
	start = raw.index(b'class CfgWalk'); end = raw.index(b'\n\nowned CfgWalk'); view = bytes(b if start <= i < end or b in (10, 13) else 32 for i, b in enumerate(raw))
	assert view[650:670] == raw[650:670]
	decl = '''struct CfgFunction { int entry; int exit; }
struct CfgBlock { int function; int origin; int role; int instruction; int terminators; int term; int condition; int yes; int no; bool reachable; }
struct CfgInstruction { int opcode; }
class CfgData {
	owned CfgFunction[] functions; owned CfgBlock[] blocks; owned CfgInstruction[] instructions;
	int function_count; int block_count;
	init() { this.functions = new CfgFunction[1]; this.blocks = new CfgBlock[2]; this.instructions = new CfgInstruction[1]; this.function_count = 1; this.block_count = 2; }
}
'''
	main = '''int main() {
	var d = new CfgData(); CfgFunction f = {entry = 1, exit = 2}; d.functions[0] = f;
	CfgBlock a = {function = 1, origin = 0, role = 0, instruction = 0, terminators = 1, term = 1, condition = 0, yes = 2, no = 0, reachable = true};
	CfgBlock b = {function = 1, origin = 0, role = 0, instruction = 0, terminators = 1, term = 3, condition = 0, yes = 0, no = 0, reachable = true};
	d.blocks[0] = a; d.blocks[1] = b; var w = new CfgWalk(); w.inspect(d);
	if (w.reachable != 2 || w.edges != 1 || w.joins != 0 || w.backedges != 0 || w.cleanups != 0 || w.loans != 0 || w.effects != 0) return 90;
	return w.reachable * 10 + w.edges;
}'''
	cases = [*CASES, ('original-CfgWalk', decl, main, 21)]
	for name, provider, entry, expected in cases:
		case = leaf/name; case.mkdir(); sources = [case/'provider.astra', case/'main.astra']
		sources[0].write_text(provider); sources[1].write_text(entry+'\n')
		if name == 'original-CfgWalk':
			p = case/'original-operation-view.astra'; p.write_bytes(view); sources.insert(1, p)
		outcomes = {}
		for mode in ('O0', 'O2'):
			product = build/(name+'-'+mode); run([c0, '-'+mode, *sources, '-o', product], name+'-build-'+mode); run([product], name+'-run-'+mode, expected)
			outcomes[mode] = dict(path=str(product), sha256=sha(product), exit=expected)
		items.append(dict(name=name, sources=[dict(path=str(p), bytes=p.stat().st_size, sha256=sha(p)) for p in sources], expected_exit=expected, C0=outcomes))
		(leaf/'selection.json').write_text(json.dumps(items, indent=2)+'\n')
		print(name, 'C0 O0/O2 frozen', flush=True)
	negative = []
	for name, source in NEGATIVES.items():
		p = leaf/(name+'.astra'); p.write_text(source+'\n'); r = run([c0, '--check', p], name+'-negative', None)
		negative.append(dict(name=name, source=str(p), sha256=sha(p), C0_exit=r.returncode, stderr=r.stderr.decode()))
	(leaf/'negatives.json').write_text(json.dumps(negative, indent=2)+'\n')
	(leaf/'original.json').write_text(json.dumps(dict(original=str(original), original_sha256=sha(original), span=[650, 664], selected_declaration=[start, end], view='original-CfgWalk/original-operation-view.astra', harness='separate CfgData storage harness retains the exact types/fields read by inspect; unused shared identity, CoreNode payload and unrelated compiler dependencies excluded. No whole CfgData/module admission is claimed.', expected_counters=[2, 1, 0, 0, 0, 0, 0]), indent=2)+'\n')


if __name__ == '__main__':
	main()
