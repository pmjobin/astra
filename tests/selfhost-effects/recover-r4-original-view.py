#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""R4 minimal dependency view: every exercised original declaration stays exact."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def declarations(dump):
	depth = 0; quoted = False; escaped = False; start = None; groups = []
	for i, char in enumerate(dump):
		if quoted:
			if escaped: escaped = False
			elif char == '\\': escaped = True
			elif char == '"': quoted = False
		elif char == '"': quoted = True
		elif char == '(':
			depth += 1
			if depth == 2: start = i
		elif char == ')':
			if depth == 2: groups.append(dump[start:i+1])
			depth -= 1
	assert depth == 0 and not quoted
	return groups


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--ledger-component', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_original_view_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-original-view-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; selections = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items()); assert sha(a.ledger_component) == read(a.ledger_component.with_suffix('.identity.json'))['sha256']
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stdout[-1500:], r.stderr[-2500:]); return r
	def view(original, ranges, name, expected_names):
		data = original.read_bytes(); selected = b'\n'.join(data[first:last] for first, last in ranges); target = leaf/name; target.write_bytes(selected)
		old = declarations(run([C0, '--dump-syntax', original], name+'-original-AST').stdout.decode()); new = declarations(run([C0, '--dump-syntax', target], name+'-view-AST').stdout.decode()); assert all(group in old for group in new)
		found = []
		for group in new:
			if group.startswith('(class '): found.append(re.search(r'^\(class "([^"]+)"', group)[1])
			if group.startswith('(function\n'): found.append(re.search(r'\(name "([^"]+)"\)', group)[1])
		assert found == expected_names, found
		selections.append(dict(original=str(original), original_sha256=sha(original), view=str(target), view_sha256=sha(target), ranges=[dict(start_byte=first, end_byte=last, sha256=hashlib.sha256(data[first:last]).hexdigest()) for first, last in ranges], declaration_names=found, AST_byte_exact=True, AST_sha256=hashlib.sha256('\n'.join(new).encode()).hexdigest()))
		return target
	source = ROOT/'compiler/source/source.astra'; data = source.read_bytes(); first = data.index(b'bool source_append_text('); last = data.index(b'\n}\n', first)+3
	source_view = view(source, [(134, 220), (first, last)], 'source-view.astra', ['SourceBoundsError', 'source_append_text'])
	scalar = ROOT/'lib/astra/text/scalar-format.astra'; data = scalar.read_bytes(); first = data.index(b'bool append_int('); last = data.index(b'\n}\n', first)+3; scalar_view = view(scalar, [(first, last)], 'scalar-view.astra', ['append_int'])
	original = ROOT/'compiler/semantic/flow-query.astra'; data = original.read_bytes(); first = data.index(b'void flow_number('); last = data.index(b'\n}\n', first)+3; function = view(original, [(first, last)], 'flow-number.astra', ['flow_number']); assert sha(function) == '8641d4ff6a1f19cc8bfc0ccbec492a8f7d4248eebcb05373c15479e7114a3e68'
	before = read(paths.RUNTIME/'original-before-O0/result.json'); inputs = [function, Path(before['inputs'][1]['path']), Path(before['inputs'][2]['path']), source_view, ROOT/'lib/astra/base/errors.astra', ROOT/'lib/astra/text/utf8-message.astra', ROOT/'lib/astra/text/utf8-byte-builder.astra', scalar_view]
	libraries = load_module('r3_original_view_providers', ROOT/'tests/selfhost-typecore/build.py'); objects = [a.component.parent/(name+'.o') for name in libraries.PROVIDERS]; links = [arg for path in objects for arg in ('--link-object', path)]; c0 = build/'C0'; run([C0, '-'+a.mode, *inputs, *links, '-o', c0], 'C0-build'); run([c0], 'C0-execute', (42,)); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', c0], 'C0-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
	target = build/'Astra.ll'; target.write_text('Original source view sentinel\n'); sentinel = sha(target); native = run([a.component, '--native', target, *inputs], 'Astra-attempt', range(9)); emitted = native.returncode == 0; boundary = None
	if emitted:
		run(['opt', '-passes=verify', '-disable-output', target], 'LLVM-verify'); obj = build/'Astra.o'; exe = build/'Astra'; run(['llc', '-filetype=obj', '-'+a.mode, target, '-o', obj], 'Astra-object'); run(['cc', '-no-pie', obj, *objects, '-o', exe], 'Astra-link'); run([exe], 'Astra-execute', (42,)); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], 'Astra-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
	else:
		assert sha(target) == sentinel; match = re.search(rb'RECOVER_FLOW ([0-9]+) ([0-9]+)', native.stdout); ledger = run([a.ledger_component, '--classstorage-source-ledger', a.mode, build/'unused', *inputs], 'source-ledger', range(9))
		if match and int(match[2]) > 0:
			for line in ledger.stdout.splitlines():
				row = line.split()
				if len(row) == 10 and row[0] == b'NODE' and int(row[1]) == int(match[2]):
					path = Path(bytes.fromhex(row[7].decode()).decode()); first, last = int(row[8]), int(row[9]); fragment = path.read_bytes()[first:last]; assert path in inputs; boundary = dict(node=int(match[2]), stage=int(match[1]), source=str(path), source_sha256=sha(path), start_byte=first, end_byte=last, fragment_sha256=hashlib.sha256(fragment).hexdigest(), first_line=fragment.decode().splitlines()[0]); break
			assert boundary
	result = dict(status='ORIGINAL_SOURCE_VIEW_EXECUTED' if emitted else 'ORIGINAL_SOURCE_VIEW_DEFERRED', profile=a.mode, component_sha256=sha(a.component), ledger_component_sha256=sha(a.ledger_component), selections=selections, excluded_modules=['lib/astra/base/diagnostics.astra: all declarations unexercised; the exact caller and selected functions and complete Classes contain no diagnostics calls; independent C0 compilation/execution validates the omission'], excluded_source_declarations=['SourceLocation', 'SourceBuffer', 'SourceSpan', 'SourceDiagnostic', 'source_normalize_path', 'source_buffer', 'source_valid_span', 'source_same_objects', 'source_same_handles', 'source_locate', 'source_path', 'source_bytes'], excluded_scalar_declarations=['append_u32', 'append_bool', 'append_u64', 'append_i64'], excluded_query_dependencies='All declarations other than the original flow_number; none is exercised by this caller.', inputs=[dict(path=str(path), sha256=sha(path)) for path in inputs], C0_actual_execution=42, Astra_emitted=emitted, Astra_actual_execution=42 if emitted else None, first_source_boundary=boundary, stdout=native.stdout.decode(), destination_preserved=not emitted, limitation='Only unexercised declarations are excluded. Original selected bytes and independent C0 syntax subtrees are exact. Real Utf8Message, Utf8ByteBuilder, scalar formatter and source_append_text functionality is retained; no substitute method, constructor or helper is introduced.'); (leaf/'result.json').write_text(json.dumps(result, indent=2)+'\n'); print(json.dumps(result, indent=2), flush=True)


if __name__ == '__main__':
	main()
