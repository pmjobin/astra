#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind the unchanged original add body and exchange to IR and native execution."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import subprocess
from state import ROOT, RUNTIME, C0, read, sha


def main():
	p = argparse.ArgumentParser(); p.add_argument('--qualification', type=Path, required=True); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--output', type=Path, required=True); a = p.parse_args()
	leaf = a.qualification; observations = leaf/'observations'; gate = read(leaf/'result.json'); assert gate['status'] == 'PASS'
	row = next(row for row in read(observations/'results.json') if row['name'] == 'original-FlowGraph-add'); assert row['baseline_complete']
	original = ROOT/'compiler/semantic/flow-model.astra'; view = RUNTIME/'corpus-v1/original-FlowGraph-view.astra'; manifest = next(row for row in read(RUNTIME/'corpus-v1/selection.json') if row['name'] == 'original-FlowGraph-add')['view']
	assert sha(original) == manifest['original_sha256']; start, end = manifest['original_add_span']; assert original.read_bytes()[start:end] == view.read_bytes()[start:end]
	assert original.read_bytes()[3589:3614] == view.read_bytes()[3589:3614] == b'swap(this.events, grown);'
	spec = importlib.util.spec_from_file_location('probe', ROOT/'tests/selfhost-classstorage/abi-probe.py'); probe = importlib.util.module_from_spec(spec); spec.loader.exec_module(probe)
	def methods(node):
		if not isinstance(node, list): return []
		result = [node] if node[:1] == ['method'] and ['name', 'add'] in node else []
		return result + [found for child in node for found in methods(child)]
	asts = []
	for name, path in [('original', original), ('view', view)]:
		r = subprocess.run([C0, '--dump-syntax', path], capture_output=True); assert r.returncode == 0
		(a.output.parent/('witness-'+a.mode+'-'+name+'-C0.syntax')).write_bytes(r.stdout); asts.append(methods(probe.syntax(r.stdout.decode())))
	assert len(asts[0]) == len(asts[1]) == 1 and asts[0] == asts[1]
	paths = dict(core=leaf/'original-FlowGraph-add-core.stdout', cfg=leaf/'original-FlowGraph-add-cfg.stdout', ssa=observations/'original-FlowGraph-add-ssa.stdout', flow=observations/'original-FlowGraph-add-admit.stdout', abi=observations/'original-FlowGraph-add.abi', symbols=observations/'original-FlowGraph-add-symbols.stdout', disassembly=observations/'original-FlowGraph-add-disassembly.stdout', elf=observations/'original-FlowGraph-add-ELF.stdout')
	text = {key: path.read_text() for key, path in paths.items()}
	nodes = {parts[1]: parts for parts in map(str.split, text['core'].splitlines()) if parts and parts[0] == 'NODE'}
	exchanges = [parts for parts in nodes.values() if parts[2] == '33' and parts[-3] == str(view).encode().hex() and parts[-2:] == ['3589', '3614']]; assert len(exchanges) == 1; exchange = exchanges[0]
	left, right = nodes[exchange[7]], nodes[exchange[8]]
	assert left[2] == right[2] == '34' and left[9] == '1' and right[9] == '2' and left[13] == right[13] == exchange[4] and int(left[10]) > 0 and int(right[10]) > 0 and left[10] != right[10]
	for node in (exchange, left, right):
		matches = [line for line in text['cfg'].splitlines() if line.startswith('INST ') and line.split()[3:5] == [node[1], node[2]] and line.split()[-3:] == node[-3:]]
		assert len(matches) == 1 and matches[0] in text['ssa']
	for suffix in ('native-execute', 'C0-execute', 'memory-native', 'memory-C0'): assert next(c for c in read(observations/'commands.json') if c['name'] == 'original-FlowGraph-add-'+suffix)['exit'] == 24
	assert all(sha(source['path']) == source['sha256'] for source in row['sources']) and all(sha(product['path']) == product['sha256'] for product in row['products'].values())
	ir = Path(row['products']['raw']['path']).read_text(); names = re.findall(r'^define [^\n]*?@([A-Za-z0-9_.]+)\(', ir, re.M); name = names[int(exchange[3])-1]
	assert '@'+name+'(' in ir and 'ELF64' in text['elf']
	result = dict(status='PASS', mode=a.mode, component_sha256=gate['component_sha256'], original=dict(path=str(original), sha256=sha(original), blob=subprocess.check_output(['git', 'hash-object', original], cwd=ROOT).decode().strip(), operation_span=[3589,3614], add_span=[start,end]), view=dict(path=str(view), sha256=sha(view), complete_add_bytes_equal=True, independently_parsed_C0_add_AST_equal=True, differences=manifest['difference']), Core_exchange=exchange, Core_left_capture=left, Core_right_capture=right, LLVM_symbol=name, products=row['products'], normal_exit_Valgrind=row['memory'], independent_layout=row['layout_comparison'], expected=dict(rows=33, capacity=64, native_and_C0_exit=24), stage_receipts={key: dict(path=str(path), sha256=sha(path)) for key,path in paths.items()}, limitation='Unchanged complete add body in a disclosed Class/dependency view. The full original FlowGraph, whole compiler and Stage 1 remain unqualified. No source-population node is promoted based only on this view.')
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print(a.mode, 'original FlowGraph.add bytes/AST/IR/native/C0/Valgrind witness bound')


if __name__ == '__main__':
	main()
