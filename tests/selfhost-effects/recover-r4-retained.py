#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Replay all 120 R3 effects inputs at their original paths and compare raw IR."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def outside_buffer_helper(data):
	pattern = rb'^define [^\n]*@astra\.e25a\.buffer\.allocate\([^\n]*\) \{[\s\S]*?\n\}\n'
	result, count = re.subn(pattern, b'R4_EXPLICIT_BUFFER_HELPER_BOUNDARY\n', data, flags=re.M); assert count == 1; return result


def resolved_nonallocator_text(data):
	# This is a disclosed textual diagnostic, never raw-byte identity or an
	# equivalence proof. Keep all constants and nonallocator instructions.
	attributes = dict(re.findall(rb'^attributes #([0-9]+) = (\{[^\n]*\})$', data, re.M))
	for name in (b'astra.e25a.buffer.allocate', b'astra.e25a.allocate'):
		pattern = rb'(?:^; Function Attrs:[^\n]*\n)?^define [^\n]*@'+re.escape(name)+rb'\([^\n]*\) [^\n]*\{[\s\S]*?\n\}\n'
		data, count = re.subn(pattern, b'R4_EXPLICIT_HELPER_BOUNDARY '+name+b'\n', data, flags=re.M); assert count == 1
	data = re.sub(rb'^attributes #[0-9]+ = \{[^\n]*\}\n', b'', data, flags=re.M)
	result = bytearray(); i = 0; quoted = False; comment = False
	while i < len(data):
		value = data[i]
		if comment:
			result.append(value); comment = value != 10; i += 1; continue
		if quoted:
			result.append(value); i += 1
			if value == 92 and i < len(data): result.append(data[i]); i += 1
			elif value == 34: quoted = False
			continue
		if value == 34: quoted = True
		if value == 59: comment = True
		if value == 35:
			end = i + 1
			while end < len(data) and 48 <= data[end] <= 57: end += 1
			if end > i + 1:
				key = data[i + 1:end]; assert key in attributes; result.extend(b'R4_RESOLVED_ATTRIBUTE'+attributes[key]); i = end; continue
		result.append(value); i += 1
	assert not quoted
	return bytes(result)


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_retained_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-retained-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	prior_runtime = paths.RUNTIME.parent/'effects25-r3'; prior_build = paths.BUILD.parent/'effects25-r3'; config = read(prior_runtime/('r3-consolidated-final6-'+a.mode)/'result.json')['profile_configuration']; names = config['native_results']+config['new_native_results']; expected_programs = []
	for name in names: expected_programs += read(prior_runtime/name/'result.json')['programs']
	assert len(expected_programs) == len({row['source_sha256'] for row in expected_programs}) == 120 and sum(row['observed_error_path'] for row in expected_programs) == 65
	def save(): (leaf/'result.json').write_text(json.dumps(dict(status='PINNED_R3_EFFECTS_REPLAY_IN_PROGRESS' if len(rows) < 120 else 'PINNED_R3_EFFECTS_REPLAY_COMPLETE', profile=a.mode, component_sha256=sha(a.component), programs=rows, native_programs=len(rows), actual_error_paths=sum(row['observed_error_path'] for row in rows), raw_LLVM_identical=sum(row['raw_LLVM_identical'] for row in rows), other_raw_definitions_identical=sum(row['other_raw_definitions_identical'] for row in rows), resolved_nonallocator_text_identical=sum(row['resolved_nonallocator_text_identical'] for row in rows), limitation='Inputs retain their original R3 absolute paths and source spans. Raw IR/ELF identities are attributed separately: C0-required zero-buffer and checked allocation-boundary corrections change shared private helpers and LLVM attribute numbering. Raw comparison excluding only the buffer helper is still measured without granting equality. The additional diagnostic excludes both complete allocation helpers and resolves attribute references outside quoted strings/comments; it never establishes raw identity or behavioral equivalence. All runtime/C0/LLVM/memory checks are fresh; no new source-program credit.'), indent=2)+'\n')
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=dict(os.environ, CCACHE_DISABLE='1'), capture_output=True, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stdout[-2000:], r.stderr[-2500:]); return r
	for name in names:
		for old in read(prior_runtime/name/'result.json')['programs']:
			key = old['name']; source = prior_runtime/name/(key+'.astra'); assert sha(source) == old['source_sha256']; old_products = prior_build/name
			for suffix, field in [('-Astra.ll', 'Astra_raw_LLVM_sha256'), ('-Astra', 'Astra_ELF_sha256'), ('-C0', 'C0_ELF_sha256')]: assert sha(old_products/(key+suffix)) == old[field]
			inputs = [source, ROOT/'lib/astra/base/errors.astra']; ir = build/(key+'-Astra.ll'); run([a.component, '--native', ir, *inputs], key+'-emit'); same = sha(ir) == old['Astra_raw_LLVM_sha256']; before = (old_products/(key+'-Astra.ll')).read_bytes(); (leaf/(key+'-R3-raw.ll')).write_bytes(before); outside = outside_buffer_helper(ir.read_bytes()); other_same = outside == outside_buffer_helper(before); resolved_same = resolved_nonallocator_text(ir.read_bytes()) == resolved_nonallocator_text(before); assert resolved_same, (key, 'unexplained textual drift beyond disclosed allocator boundaries and attribute resolution', sha(ir), old['Astra_raw_LLVM_sha256'])
			run(['llvm-as', ir, '-o', build/(key+'.bc')], key+'-assemble'); run(['opt', '-passes=verify', '-disable-output', ir], key+'-verify'); optimized = build/(key+'-'+a.mode+'.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', ir, '-o', optimized], key+'-optimize'); run(['opt', '-passes=verify', '-disable-output', optimized], key+'-optimized-verify'); obj = build/(key+'.o'); exe = build/(key+'-Astra'); run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], key+'-object'); run(['cc', '-no-pie', obj, '-o', exe], key+'-link'); run([exe], key+'-execute', (42,))
			c0 = build/(key+'-C0'); run([C0, '-'+a.mode, *inputs, '-o', c0], key+'-C0-build'); run([c0], key+'-C0-execute', (42,))
			for label, program in [('Astra', exe), ('C0', c0)]:
				memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', program], key+'-'+label+'-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
			assert (leaf/(key+'-execute.stdout')).read_bytes() == (leaf/(key+'-C0-execute.stdout')).read_bytes() and (leaf/(key+'-execute.stderr')).read_bytes() == (leaf/(key+'-C0-execute.stderr')).read_bytes()
			rows.append(dict(name=key, source_path=str(source), source_sha256=sha(source), old_raw_LLVM_sha256=old['Astra_raw_LLVM_sha256'], raw_LLVM_sha256=sha(ir), raw_LLVM_identical=same, other_raw_definitions_identical=other_same, resolved_nonallocator_text_identical=resolved_same, raw_drift_reason=None if same else 'C0-compatible zero-buffer policy and non-inlined checked allocator; full original/current raw IR and strict byte comparisons retained separately', ELF_sha256=sha(exe), ELF_identical=sha(exe) == old['Astra_ELF_sha256'], C0_ELF_sha256=sha(c0), C0_ELF_identical=sha(c0) == old['C0_ELF_sha256'], observed_error_path=old['observed_error_path'], returning_Valgrind='zero unsuppressed errors and live allocations')); save(); print(a.mode, key, 'exact input retained; raw identity', same, '; fresh C0/native execution and memory pass', flush=True)
	assert len(rows) == 120


if __name__ == '__main__':
	main()
