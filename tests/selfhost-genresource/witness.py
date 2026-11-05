#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Freeze unchanged real frontier functions in explicitly disclosed source views."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
from state import ROOT, RUNTIME, C0, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--version',default='v2'); a = p.parse_args()
	assert a.version.replace('-','').isalnum()
	leaf = RUNTIME/('witness-input-'+a.version); leaf.mkdir(exist_ok=False)
	initial = read(RUNTIME/'initial/result.json'); stop = initial['cohorts']['Class15-current']['stop']; original = Path(stop['path']); raw = original.read_bytes()
	assert sha(original) == next(row['sha256'] for row in initial['cohorts']['Class15-current']['files'] if row['path'] == str(original))
	start,end = stop['start'],stop['end']; body = raw[start:end]; assert body.startswith(b'bool outlives(') and body.endswith(b'\t}')
	begin = raw.index(b'struct FlowRegion {'); finish = raw.index(b'\n}',begin)+2
	view = bytearray(byte if byte == 10 else 32 for byte in raw); view[begin:finish] = raw[begin:finish]
	prefix = b'class FlowGraph {\n\towned FlowRegion[] regions;\n\tint region_count;\n\tinit() { this.regions = new FlowRegion[4]; this.region_count = 4; }\n\t'
	place = start-len(prefix); assert place > finish
	view[place:start] = prefix; view[start:end] = body; view[end:end+3] = b'\n}\n'
	path = leaf/'FlowGraph-view.astra'; path.write_bytes(view); assert path.read_bytes()[start:end] == body
	provider = leaf/'provider.astra'; provider.write_text('struct SyntaxNodeId { int index; }\n')
	driver = leaf/'main.astra'; driver.write_text('''int main() {
	var graph = new FlowGraph();
	FlowRegion first = {parent = 0, node = {index = 1}}; FlowRegion second = {parent = 1, node = {index = 2}};
	FlowRegion third = {parent = 2, node = {index = 3}}; FlowRegion fourth = {parent = 4, node = {index = 4}};
	graph.regions[0] = first; graph.regions[1] = second; graph.regions[2] = third; graph.regions[3] = fourth;
	if (!graph.outlives(1,3) || !graph.outlives(2,3) || !graph.outlives(3,3)) return 90;
	if (graph.outlives(3,1) || graph.outlives(1,0) || graph.outlives(1,5) || graph.outlives(1,4)) return 91;
	return 54;
}
''')
	spec = importlib.util.spec_from_file_location('probe',ROOT/'tests/selfhost-classstorage/abi-probe.py'); probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)
	def method(node):
		if not isinstance(node,list): return []
		return ([node] if node[:1] == ['method'] and ['name','outlives'] in node else [])+[found for child in node for found in method(child)]
	asts = []
	for name, source in [('original',original),('view',path)]:
		r = subprocess.run([C0,'--dump-syntax',source],capture_output=True); assert r.returncode == 0
		(leaf/(name+'.syntax')).write_bytes(r.stdout); asts.append(method(probe.syntax(r.stdout.decode())))
	assert len(asts[0]) == len(asts[1]) == 1 and asts[0] == asts[1]
	item = dict(name='original-FlowGraph-outlives',sources=[dict(path=str(p),bytes=p.stat().st_size,sha256=sha(p)) for p in (provider,path,driver)],expected_exit=54,oracle='Independent ancestor-chain, reflexive, invalid-range and cyclic-parent termination assertions; manual 54',view=dict(original_path=str(original),original_sha256=sha(original),span=[start,end],original_body_hex=body.hex(),view_sha256=sha(path),C0_AST_equal=True,differences='Unchanged complete outlives method and FlowRegion declaration at original byte offsets. Other FlowGraph members omitted; disclosed constructor creates four region rows; standalone SyntaxNodeId provider. This does not qualify the complete original Class or frozen compiler.'))
	(leaf/'selection.json').write_text(json.dumps([item],indent=2)+'\n'); print('Byte-exact original FlowGraph.outlives body and independent C0 method AST preserved')


if __name__ == '__main__':
	main()
