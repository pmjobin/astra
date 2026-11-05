#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze the six additional original FlowGraph exchanges as disclosed views."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
from state import ROOT, RUNTIME, BUILD, C0, sha


def main():
	parser = argparse.ArgumentParser(); parser.add_argument('--name', default='family-v3'); args = parser.parse_args(); assert args.name.replace('-', '').isalnum()
	leaf = RUNTIME/args.name; leaf.mkdir(exist_ok=False); build = BUILD/(args.name+'-oracles'); build.mkdir(exist_ok=False); commands = []
	raw = (ROOT/'compiler/semantic/flow-model.astra').read_bytes(); class_start = raw.index(b'class FlowGraph {')
	provider = leaf/'provider.astra'; provider.write_text('struct SyntaxSourceId { int index; }\nstruct SyntaxNodeId { int index; }\nstruct SymbolId { int index; }\nstruct TypeId { int index; }\nstruct SyntaxSpan { SyntaxSourceId source; int start; int end; }\n')
	cases = [('regions', 'FlowRegion', '{parent = 11, node = {index = 3}}', 'parent', 11), ('slots', 'FlowSlot', '{symbol = {index = 1}, type = {index = 2}, flags = 12, region = 3, owner = false, parameter = false}', 'flags', 12), ('loans', 'FlowLoan', '{source = 13, borrower = 2, region = 3, node = {index = 0}, call = {index = 0}}', 'source', 13), ('obligations', 'FlowObligation', '{node = {index = 0}, reason = 14}', 'reason', 14), ('values', 'FlowNullValue', '{node = {index = 15}}', 'node.index', 15), ('fields', 'FlowField', '{root = 16, parent = 0, symbol = {index = 1}, type = {index = 2}, flags = 0, leaf = true}', 'root', 16)]
	selection = []
	for field, element, initializer, member, value in cases:
		statement = ('swap(this.'+field+', grown);').encode(); start = raw.index(statement); end = start + len(statement)
		view = bytearray(b if b == 10 else 32 for b in raw); view[:class_start] = raw[:class_start]
		prefix = ('class FlowGraph {\n\towned '+element+'[] '+field+';\n\tinit() { this.'+field+' = new '+element+'[1]; }\n\tvoid grow() { var grown = new '+element+'[3]; grown[0] = this.'+field+'[0];\n').encode()
		# Keep the original operation offset while bounding the disclosed wrapper's
		# source span. Generic private names encode that span; thousands of blank
		# bytes inside a Class can exceed the unchanged 65536-byte name bound.
		wrapper_start = start - len(prefix) - 1; assert wrapper_start >= class_start
		view[wrapper_start:wrapper_start+len(prefix)] = prefix; view[start:end] = raw[start:end]; view[end:end+5] = b'\n}\n}\n'
		path = leaf/(field+'-view.astra'); path.write_bytes(view); assert view[start:end] == statement
		main = leaf/(field+'-main.astra'); main.write_text('int main() { var graph = new FlowGraph(); '+element+' row = '+initializer+'; graph.'+field+'[0] = row; graph.grow(); if (len(graph.'+field+') != 3 || graph.'+field+'[0].'+member+' != '+str(value)+') return 99; return '+str(value)+'; }\n')
		selection.append(dict(name='original-'+field+'-exchange', sources=[dict(path=str(p), bytes=p.stat().st_size, sha256=sha(p)) for p in (provider, path, main)], expected_exit=value, source_operation=dict(original_sha256=sha(ROOT/'compiler/semantic/flow-model.astra'), span=[start,end], bytes=statement.decode()), limitation='Exact original operation and record declarations in a disclosed bounded growth wrapper. The original containing method is not claimed qualified.'))
		for mode in ('O0', 'O2'):
			target = build/(field+'-'+mode)
			for phase, argv, expected in [('compile', [C0, '-'+mode, provider, path, main, '-o', target], 0), ('execute', [target], value)]:
				name = field+'-'+mode+'-'+phase; begin = time.monotonic(); r = subprocess.run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *map(str, argv)], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'))
				(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=list(map(str, argv)), expected=expected, exit=r.returncode, start=begin, end=time.monotonic())); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode == expected and r.stdout == r.stderr == b'', (name,r.stderr)

	(leaf/'selection.json').write_text(json.dumps(selection, indent=2)+'\n'); print('Six unchanged same-family source exchanges independently C0/manual qualified in disclosed wrappers at O0/O2')


if __name__ == '__main__':
	main()
