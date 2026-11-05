#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Bind original byte spans to verified application IR and native products."""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def sha(path):
	with Path(path).open('rb') as stream: return hashlib.file_digest(stream, 'sha256').hexdigest()


def read(path):
	return json.loads(Path(path).read_text())


def main():
	p = argparse.ArgumentParser()
	for name in ('before', 'after', 'original', 'qualification', 'output'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True); a = p.parse_args()
	before, after = read(a.before), read(a.after); original = read(a.original/'result.json')
	leaf = a.qualification/('new-'+a.mode); observations = leaf/'observations'
	gate = read(leaf/'result.json'); assert gate['status'] == 'PASS' and gate['mode'] == a.mode
	row = next(row for row in read(observations/'results.json') if row['name'] == 'original-Utf8Message'); assert row['baseline_complete']
	assert all(sha(source['path']) == source['sha256'] for source in row['sources'])
	assert all(sha(product['path']) == product['sha256'] for product in row['products'].values())
	source = Path(original['original']['path']); view = Path(original['view']['path'])
	assert sha(source) == original['original']['sha256'] and sha(view) == original['view']['sha256']
	declaration = original['original']['declaration']; start, end = declaration['start'], declaration['end']
	assert source.read_bytes()[start:end] == view.read_bytes()[start:end] and len(source.read_bytes()) == len(view.read_bytes())
	assert original['identical_C0_declaration_AST'] and original['C0'][a.mode]['exit'] == 8
	bag = ROOT/'lib/astra/collections/bag.astra'; bag_sha = sha(bag)
	assert bag_sha == 'cb292b3c8d9af01c43eac0ca8a0bbfe28597487ef564eb28b70162b099705afd'
	paths = dict(core=leaf/'original-Utf8Message-core.stdout', cfg=leaf/'original-Utf8Message-cfg.stdout', ssa=observations/'original-Utf8Message-ssa.stdout', flow=observations/'original-Utf8Message-admit.stdout', abi=observations/'original-Utf8Message.abi', symbols=observations/'original-Utf8Message-symbols.stdout', disassembly=observations/'original-Utf8Message-disassembly.stdout', elf=observations/'original-Utf8Message-ELF.stdout')
	texts = {name:path.read_text() for name, path in paths.items()}
	assert texts['flow'].startswith('astra-flow/4\nSTATUS 0 0\n')
	assert texts['core'].startswith('astra-core/1\n') and texts['cfg'].startswith('astra-cfg/1\n') and texts['ssa'].startswith('astra-ssa/1\n')
	functions = [line for line in texts['ssa'].splitlines() if line.startswith('FUNCTION ')]
	assert functions and all([line for line in texts[stage].splitlines() if line.startswith('FUNCTION ')] == functions for stage in ('core', 'cfg'))
	abi_functions = [line.split() for line in texts['abi'].splitlines() if line.startswith('FUNCTION ')]; assert len(abi_functions) == len(functions)
	ir = Path(row['products']['raw']['path']).read_text()
	names = re.findall(r'^define [^\n]*?@([A-Za-z0-9_.]+)\(', ir, re.M)
	assert len(names) >= len(functions) and 'astra.text.snapshot' in names and 'astra.text.equal' in names
	assert '@memcpy(' in ir and '@memcmp(' in ir and '@free(' in ir
	witnesses = []
	for line, abi in zip(functions, abi_functions):
		parts = line.split(); ordinal, symbol, signature = map(int, parts[1:4]); actual_path = bytes.fromhex(parts[-3]).decode(); first, last = map(int, parts[-2:])
		assert (int(abi[1]), int(abi[2]), int(abi[3]), int(abi[-2]), int(abi[-1])) == (ordinal, symbol, signature, first, last)
		if actual_path not in (str(bag), str(view)): continue
		original_path = str(bag) if actual_path == str(bag) else str(source); digest = bag_sha if actual_path == str(bag) else sha(source)
		old = [node for node in before['nodes'] if node['path'].endswith('/'+str(Path(original_path).relative_to(ROOT))) and node['source_sha256'] == digest and (node['start'], node['end']) == (first, last) and node['syntax_kind'] in (44, 52)]
		new = [node for node in after['nodes'] if node['source_sha256'] == digest and (node['start'], node['end']) == (first, last) and node['syntax_kind'] in (44, 52)]
		assert len(old) == len(new) == 1, (original_path, first, last)
		name = names[ordinal - 1]
		retained = any(line.split()[-1:] == [name] for line in texts['symbols'].splitlines())
		if not retained: continue
		assert '<'+name+'>:' in texts['disassembly']
		witnesses.append(dict(original_path=original_path, original_sha256=digest, original_node=old[0]['node'], syntax_kind=old[0]['syntax_kind'], start=first, end=last, before_observed_type=old[0]['type'], after_observed_type=new[0]['type'], application_source_path=actual_path, mapping='Exact complete Bag source' if actual_path == str(bag) else 'Exact selected Class declaration; outside bytes are whitespace, with every original offset retained', Core_CFG_SSA_function=line, physical_ABI_function=' '.join(abi), LLVM_symbol=name, symbol_retained_in_native_object=True))
	assert any(row['original_path'] == str(source) for row in witnesses)
	assert sum(row['original_path'] == str(bag) for row in witnesses) >= 3
	commands = read(observations/'commands.json')
	for name in ('native-execute', 'C0-execute', 'memory-native', 'memory-C0'):
		assert next(command for command in commands if command['name'] == 'original-Utf8Message-'+name)['exit'] == 8
	assert b'ELF64' in paths['elf'].read_bytes() and b'Advanced Micro Devices X86-64' in paths['elf'].read_bytes()
	assert 'TYPE 15 15 16 8 ' in texts['abi'] and 'TYPE 15 15 ' in texts['core']
	text_fields = [line for line in texts['flow'].splitlines() if line.startswith('FIELD ') and line.split()[6] == '15']; assert text_fields
	result = dict(format='astra-textclass-original-source-to-native/1', status='PASS', mode=a.mode, component_sha256=gate['component_sha256'], original_Class=original['original'], original_declaration_view=original['view'], original_complete_C0_module=original['C0'][a.mode], before_ledger_sha256=sha(a.before), after_ledger_sha256=sha(a.after), source_functions=witnesses, actual_Flow_text_fields=text_fields, stage_receipts={name:dict(path=str(path), sha256=sha(path)) for name, path in paths.items()}, products=row['products'], independent_layout=row['layout_comparison'], normal_memory=row['memory'], native_and_C0_exit=8, limitation='Only the original Bag bodies and byte-exact original Utf8Message Class declaration are witnessed. Property reads are checked projections, not separately executable getters. The complete original exception/factory module, text_split, full compiler-source safety and Stage 1 remain DEFERRED. Whole-source typed observations are not relabelled as native safety proofs.')
	with a.output.open('x') as out: out.write(json.dumps(result, indent=2)+'\n')
	print(a.mode, len(witnesses), 'original source function spans mapped through verified IR, ABI, LLVM, ELF and paired native/C0 observations')


if __name__ == '__main__':
	main()
