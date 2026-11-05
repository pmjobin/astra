#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind the original index/member spans to checked IR and executing native ELF."""
import argparse
import json
from pathlib import Path
import re
from state import ROOT, RUNTIME, read, sha


def main():
	p = argparse.ArgumentParser()
	for name in ('qualification', 'before', 'after', 'output'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	leaf = a.qualification/('new-'+a.mode); observations = leaf/'observations'
	gate = read(leaf/'result.json'); assert gate['status'] == 'PASS'
	row = next(row for row in read(observations/'results.json') if row['name'] == 'original-index-operation'); assert row['baseline_complete']
	original = ROOT/'compiler/cfg/consume.astra'; view = next(Path(source['path']) for source in row['sources'] if source['path'].endswith('original-operation-view.astra'))
	assert sha(original) == 'f0e32ad005bc4a2d10244821bb84ab815c4aab7332654002066cd470382033c0'
	manifest = read(RUNTIME/'operation-v1/result.json'); start, end = manifest['original']['operation_span']; assert original.read_bytes()[start:end] == view.read_bytes()[start:end]
	assert manifest['independent_C0_operation_AST_equal']
	assert all(sha(source['path']) == source['sha256'] for source in row['sources']) and all(sha(product['path']) == product['sha256'] for product in row['products'].values())
	before, after = read(a.before), read(a.after)
	paths = dict(core=leaf/'original-index-operation-core.stdout', cfg=leaf/'original-index-operation-cfg.stdout', ssa=observations/'original-index-operation-ssa.stdout', flow=observations/'original-index-operation-admit.stdout', abi=observations/'original-index-operation.abi', symbols=observations/'original-index-operation-symbols.stdout', disassembly=observations/'original-index-operation-disassembly.stdout', elf=observations/'original-index-operation-ELF.stdout')
	text = {name: path.read_text() for name, path in paths.items()}; assert text['flow'].startswith('astra-flow/4\nSTATUS 0 0\n')
	functions = [line for line in text['core'].splitlines() if line.startswith('FUNCTION ')]
	assert functions and all([line for line in text[stage].splitlines() if line.startswith('FUNCTION ')] == functions for stage in ('cfg', 'ssa'))
	core_rows = [line.split() for line in text['core'].splitlines() if line.startswith('NODE ')]
	index = [parts for parts in core_rows if parts[2] == '19' and bytes.fromhex(parts[-3]).decode() == str(view) and list(map(int, parts[-2:])) == [650, 664]]
	field = [parts for parts in core_rows if parts[2] == '30' and bytes.fromhex(parts[-3]).decode() == str(view) and list(map(int, parts[-2:])) == [650, 670]]
	assert len(index) == len(field) == 1; index, field = index[0], field[0]
	assert field[7] == index[1] and field[5] == '1' and field[6] == index[6] == '0' and field[10] == '0' and int(index[10]) > 0
	checked = {parts[1]: parts for parts in map(str.split, text['core'].splitlines()) if parts and parts[0] == 'CHECKED'}
	for node in (index, field):
		use = checked[node[4]]; assert use[2] == node[5] and use[4] == '0' and use[-3:] == node[-3:]
	type_id = index[5]; assert any(line.startswith('TYPE '+type_id+' 30 ') for line in text['core'].splitlines())
	assert 'TYPE '+type_id+' 30 8 4 2' in text['abi']
	cfg = [line.split() for line in text['cfg'].splitlines() if line.startswith('INST ')]
	for node in (index, field):
		matches = [r for r in cfg if r[3] == node[1] and r[4] == node[2] and r[-3:] == node[-3:]]; assert len(matches) == 1
		assert ' '.join(matches[0]) in text['ssa']
	frozen_nodes = []
	for data in (before, after):
		matches = [r for r in data['nodes'] if r['path'].endswith('/compiler/cfg/consume.astra') and r['source_sha256'] == sha(original) and (r['start'], r['end']) == (650, 664)]
		assert len(matches) == 1; frozen_nodes.append({key: matches[0][key] for key in ('node', 'syntax_kind', 'start', 'end', 'source_sha256', 'type', 'deferred')})
	assert all(frozen_nodes[0][key] == frozen_nodes[1][key] for key in ('node', 'syntax_kind', 'start', 'end', 'source_sha256'))
	function = next(line for line in functions if int(line.split()[1]) == int(index[3])); assert int(function.split()[-2]) < 650 and int(function.split()[-1]) > 670
	ir = Path(row['products']['raw']['path']).read_text(); names = re.findall(r'^define [^\n]*?@([A-Za-z0-9_.]+)\(', ir, re.M); name = names[int(index[3])-1]
	assert '@'+name+'(' in ir and 'icmp uge i32' in ir and 'getelementptr' in ir and 'extractvalue' in ir
	retained = any(line.split()[-1:] == [name] for line in text['symbols'].splitlines())
	if retained: assert '<'+name+'>:' in text['disassembly']
	assert 'ELF64' in text['elf'] and 'Advanced Micro Devices X86-64' in text['elf']
	commands = read(observations/'commands.json')
	for suffix in ('native-execute', 'C0-execute', 'memory-native', 'memory-C0'): assert next(c for c in commands if c['name'] == 'original-index-operation-'+suffix)['exit'] == 25
	result = dict(status='PASS', mode=a.mode, component_sha256=gate['component_sha256'], original=dict(path=str(original), sha256=sha(original), index_span=[650, 664], projection_span=[650, 670], operation_span=[start, end]), view=dict(path=str(view), sha256=sha(view), C0_operation_AST_equal=True), frozen_original_nodes=frozen_nodes, checked_index=checked[index[4]], checked_field=checked[field[4]], Core_index=index, Core_projection=field, function=function, LLVM_symbol=name, ELF_symbol_retained=retained, native_and_C0_exit=25, independent_expected_counters=dict(reachable=2, edges=2, backedges=1), independent_layout=row['layout_comparison'], normal_exit_Valgrind=row['memory'], stage_receipts={name: dict(path=str(path), sha256=sha(path)) for name, path in paths.items()}, products=row['products'], limitation='The byte-exact original d.functions[f].entry operation executes in a separately disclosed wrapper and bounded CFG driver. The complete CfgWalk.inspect body remains native-SSA resource-DEFERRED at unchanged 8000000 steps. This does not qualify the complete original CfgData shared identity, unused CoreNode payload, exception wrappers, original full module, whole compiler-source safety or Stage 1. Unvisited frozen-cohort nodes are not relabelled as typed or safe.')
	a.output.write_text(json.dumps(result, indent=2)+'\n'); print(a.mode, 'original d.functions[f].entry bound through checked types, Core/CFG/SSA, LLVM and native/C0/Valgrind execution')


if __name__ == '__main__':
	main()
