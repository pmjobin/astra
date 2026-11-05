#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind unchanged add_signature bytes/AST to actual captures and native products."""
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
from state import ROOT, RUNTIME, C0, read, sha


def methods(node):
	if not isinstance(node,list): return []
	return ([node] if node[:1] == ['method'] and ['name','add_signature'] in node else [])+[found for child in node for found in methods(child)]


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode',choices=('O0','O2'),required=True); a = p.parse_args()
	leaf = RUNTIME/('qualified-v1-'+a.mode); gate = read(leaf/'result.json'); assert gate['status'] == 'PASS'
	item = next(row for row in read(RUNTIME/'corpus-v3/selection.json') if row['name'] == 'original-add-signature')
	row = next(row for row in gate['programs'] if row['name'] == item['name']); assert row['baseline_complete']
	original = Path(item['view']['original']); view = Path(item['sources'][1]['path']); start,end = item['view']['method_span']
	assert sha(original) == item['view']['original_sha256'] and original.read_bytes()[start:end] == view.read_bytes()[start:end]
	spec = importlib.util.spec_from_file_location('probe',ROOT/'tests/selfhost-classstorage/abi-probe.py'); probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)
	asts = []
	for name,path in [('original',original),('view',view)]:
		r = subprocess.run([C0,'--dump-syntax',path],capture_output=True); assert r.returncode == 0
		(leaf/('witness-'+name+'.syntax')).write_bytes(r.stdout); asts.append(methods(probe.syntax(r.stdout.decode())))
	assert len(asts[0]) == len(asts[1]) == 1 and asts[0] == asts[1]
	text = (leaf/'original-add-signature-core.stdout').read_text()
	nodes = {parts[1]:parts for parts in map(str.split,text.splitlines()) if parts and parts[0] == 'NODE'}
	swap_start = original.read_bytes().index(b'swap(this.signatures, grown);',start); swap_end = swap_start+len(b'swap(this.signatures, grown);')
	exchanges = [parts for parts in nodes.values() if parts[2] == '33' and parts[-3:] == [str(view).encode().hex(),str(swap_start),str(swap_end)]]; assert len(exchanges) == 1
	exchange = exchanges[0]; left,right = nodes[exchange[7]],nodes[exchange[8]]
	assert left[2] == right[2] == '34' and left[9] == '1' and right[9] == '2' and left[10] != right[10] and int(left[10]) > 0 and int(right[10]) > 0
	for stage,path in [('cfg',leaf/'original-add-signature-cfg.stdout'),('ssa',leaf/'observations/original-add-signature-ssa.stdout')]:
		data = path.read_text()
		for node in (exchange,left,right):
			assert any(line.startswith('INST ') and line.split()[3:5] == [node[1],node[2]] and line.split()[-3:] == node[-3:] for line in data.splitlines()),stage
	assert all(sha(s['path']) == s['sha256'] for s in row['sources']) and all(sha(p['path']) == p['sha256'] for p in row['products'].values())
	result = dict(status='PASS',mode=a.mode,original=item['view'],view_sha256=sha(view),method_bytes_equal=True,C0_method_AST_equal=True,swap_span=[swap_start,swap_end],Core_exchange=exchange,Core_captures=[left,right],products=row['products'],independent_layout=row['layout_comparison'],normal_return_memory=row['memory'],expected=dict(rows=65,capacity=128,exit=53),limitation='The complete original method is byte-preserved in the disclosed bounded Class/dependency view. Full CheckedIndex, full compiler admission, Stage 1 and release remain unqualified.')
	(RUNTIME/('witness-'+a.mode+'.json')).write_text(json.dumps(result,indent=2)+'\n'); print(a.mode,'unchanged add_signature bytes / independent AST / Core / CFG / SSA / LLVM / native / C0 / ABI / Valgrind bound')


if __name__ == '__main__':
	main()
