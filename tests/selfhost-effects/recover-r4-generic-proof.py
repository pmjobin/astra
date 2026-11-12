#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent C0-valid deferred argument controls for generic call proof state."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def corpus():
	reader = 'class Reader { private int bias; init() { this.bias = 41; } int read(int value) { return value + this.bias; } } '
	checked = 'class Reader { private int bias; init() { this.bias = 41; } int read(int value) throws Error { if (value < 0) { throw new Error("negative"); } return value + this.bias; } } '
	repository = 'class Repository { private int value; init() { this.value = 1; } property int count { get { return this.value + 0; } } } '
	main = 'int main() { try { var repository = new Repository(); var reader = new Reader(); return reader.read(repository.count); } catch (Error caught) { return 3; } }\n'
	return [('complete-arguments', False, reader+'int main() { var reader = new Reader(); return reader.read(1); }\n'), ('deferred-ordinary-argument', True, repository+reader+main), ('deferred-checked-argument', True, repository+checked+main)]


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--expect-broken', action='store_true'); p.add_argument('--source-only', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_generic_proof_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-generic-proof-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items()); commands = []; rows = []
	def run(argv, name, allowed=(0,)):
		argv = list(map(str, argv)); start = time.monotonic(); env = dict(os.environ, CCACHE_DISABLE='1'); env.pop('LD_PRELOAD', None); env.pop('VALGRIND_OPTS', None); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=env, capture_output=True, timeout=240); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stderr[-2000:]); return r
	for name, deferred, text in corpus():
		source = leaf/(name+'.astra'); source.write_text(text); inputs = [source, ROOT/'lib/astra/base/errors.astra']; exe = build/(name+'-C0'); run([C0, '-'+a.mode, *inputs, '-o', exe], name+'-C0-build'); run([exe], name+'-C0-execute', (42,)); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-C0-memory', (42,)); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
		observed = run([a.component, '--r4-source-policy', *inputs], name+'-observe'); status = re.search(rb'^R4_CHECKED ([0-9]+) ([0-9]+) ([0-9]+)$', observed.stdout, re.M); assert status; actual = list(map(int, status.groups())); expected = [3, 0, 25 if deferred and a.expect_broken else 0]; assert actual == expected, (name, actual, expected, observed.stdout[-2000:])
		if not a.expect_broken: assert re.findall(rb'^R4_PROFILE (.+)$', observed.stdout, re.M) == [b'PRIVATE_FIELDED_EFFECTS']
		# The complete private profile now admits the computed getter and its
		# enclosing method call. The retained profile below still records 15/17.
		proof_count = len(re.findall(rb'^R4_CALL ', observed.stdout, re.M)); assert proof_count == (1 if not deferred or a.expect_broken else 2)
		owner = run([a.component, '--r1-owner-trace', a.mode, build/(name+'-owner-unused'), *inputs], name+'-owner-observe'); declarations = [line.split() for line in owner.stdout.splitlines() if line.startswith(b'DECLARATION ')]; original = [int(r[1]) for r in declarations if r[3] == b'11' and r[-1] == b'72656164']; assert len(original) == 1
		signatures = [line.split() for line in owner.stdout.splitlines() if line.startswith(b'SIGNATURE ')]; retained = any(int(r[1]) == original[0] for r in signatures); assert retained == (name == 'deferred-checked-argument' and not a.expect_broken), (name, original, retained)
		matched = [None]
		if not a.source_only:
			ledger = run([a.component, '--classstorage-source-ledger', a.mode, build/(name+'-unused'), *inputs], name+'-ledger', range(9)); call = b'reader.read(repository.count)' if deferred else b'reader.read(1)'; first = source.read_bytes().index(call); last = first + len(call); matched = []
			for line in ledger.stdout.splitlines():
				parts = line.split()
				if len(parts) == 10 and parts[0] == b'NODE' and bytes.fromhex(parts[7].decode()).decode() == str(source) and (int(parts[8]), int(parts[9])) == (first, last): matched.append(list(map(int, parts[4:7])))
			expected_use = {'complete-arguments': [1, 0, 0], 'deferred-ordinary-argument': [0, 0, 15], 'deferred-checked-argument': [0, 0, 17]}[name]; assert matched == [expected_use], (name, matched, expected_use)
		rows.append(dict(name=name, source_sha256=sha(source), C0_ELF_sha256=sha(exe), C0_exit=42, source_check=actual, completed_call_proofs=proof_count, original_method_symbol=original[0], original_signature_retained=retained, retained_call_use=matched[0], deferred_input=deferred)); print(a.mode, name, actual, 'C0 executes 42 with clean unsuppressed memory', flush=True)
	(leaf/'result.json').write_text(json.dumps(dict(status='REPRODUCED_INCOMPLETE_GENERIC_CALL_PROOF' if a.expect_broken else 'FOCUSED_GENERIC_CALL_PROOF_OBSERVATIONS' if a.source_only else 'INDEPENDENT_GENERIC_CALL_PROOF_CONTROLS', profile=a.mode, component_sha256=sha(a.component), programs=rows, semantic_profiles=dict(call_proof='Explicit private checked_build_effects_profile', retained_use_ledger='Retained checked_build_profile, field_effects false', original_method_signature='Retained checked_build_profile, field_effects false'), primary_native_credit=0, limitation='Conditional result typing is separate from a completed generic call proof. The retained ledger leaves unsupported computed getter calls untyped (15/17); it is not the private specialization profile. Frozen FlowGraph 17/19 facts are checked separately. No owner root, native array operation or native program credit is manufactured.'), indent=2)+'\n')


if __name__ == '__main__':
	main()
