#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent reservation/slot controls and LLVM-valid owner alternatives."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, bounded_run, read, sha

FIXTURE = '''int later(bool fail) throws Error { if (fail) { throw new RuntimeError("kept"); } return 7; }
int consume(owned int[] value, int extra) { return len(value) + extra; }
owned int[] relay(owned int[] value, bool fail) throws Error { if (fail) { throw new Error("kept"); } return move value; }
int main() { var spare = new int[5]; var input = new int[2]; try { return consume(move input, later(true)); } catch (Error caught) { if (caught.message == "kept") return len(input) + 40; return 4; } }
'''
SEMANTIC = ['owner slot falsely non-owning', 'move captures catch borrow', 'move reservation erased', 'unique owner consumer erased', 'later-argument abort omitted', 'move uses no actual slot', 'commit before later argument', 'abort replaced by consuming commit', 'cleanup rank changed', 'owned success SSA channel erased', 'reservation promoted to owned SSA value', 'source group aliases hidden success storage', 'result ownership qualifier erased', 'success carrier replaced with bool', 'source argument order swapped', 'buffer allocation confused with Error owner']
PHYSICAL = ['early move disarm', 'commit leaves caller armed', 'abort disarms caller', 'owner backing free skipped', 'initialized owner left unarmed', 'success stored through input data pointer', 'cleanup ignores armed state', 'wrong buffer element extent']


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('owner_negative_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('owner-adversarial-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']; assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	source = leaf/'fixture.astra'; source.write_text(FIXTURE); inputs = [source, ROOT/'lib/astra/base/errors.astra']; commands = []
	def run(argv, name, allowed):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.stdout[-2000:], r.stderr[-3000:]); return r
	c0 = build/'C0'; run([C0, '-'+a.mode, *inputs, '-o', c0], 'C0-build', {0}); run([c0], 'C0-execute', {42})
	base = build/'positive.ll'; run([a.component, '--native', base, *inputs], 'positive-emit', {0}); run(['opt', '-passes=verify', '-disable-output', base], 'positive-verify', {0}); optimized = build/'positive-optimized.ll'; run(['opt', '-passes=default<'+a.mode+'>', '-S', base, '-o', optimized], 'positive-optimize', {0}); obj = build/'positive.o'; exe = build/'positive'; run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], 'positive-object', {0}); run(['cc', '-no-pie', obj, '-o', exe], 'positive-link', {0}); run([exe], 'positive-execute', {42})
	for label, program in [('Astra', exe), ('C0', c0)]:
		memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', program], label+'-memory', {42}); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
	r = run([a.component, '--owner-adversarial', build, *inputs], 'stage-negatives', {0}); semantic = [(int(c), int(s)) for c, s in re.findall(rb'RECOVER_OWNER_REJECT ([0-9]+) ([0-9]+)', r.stdout)]; physical = [int(c) for c in re.findall(rb'RECOVER_OWNER_LLVM_REJECT ([0-9]+)', r.stdout)]
	expected = [(i, 2 if i in (0, 1, 14) else 3 if i in (2, 3, 4, 5, 15) else 4 if i <= 8 else 5 if i <= 10 else 6) for i in range(16)]; assert semantic == expected and physical == list(range(8)); variants = []
	for category in physical:
		ir = build/('owner-physical-'+str(category)+'.ll'); assert sha(ir) != sha(base); run(['llvm-as', ir, '-o', build/('owner-'+str(category)+'.bc')], 'physical-'+str(category)+'-assemble', {0}); run(['opt', '-passes=verify', '-disable-output', ir], 'physical-'+str(category)+'-verify', {0}); target = build/('owner-'+str(category)+'-optimized.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', ir, '-o', target], 'physical-'+str(category)+'-optimize', {0}); run(['opt', '-passes=verify', '-disable-output', target], 'physical-'+str(category)+'-optimized-verify', {0})
		row = dict(category=category, meaning=PHYSICAL[category], LLVM_sha256=sha(ir), semantic_rejection='Actual Astra physical verifier rejected an LLVM-valid variant')
		if category == 3:
			# A raw O0 twin preserves the allocation witness even when O2 removes
			# unused storage. This probe is separate from the target-profile IR.
			obj = build/'leak-witness.o'; exe = build/'leak-witness'; run(['llc', '-filetype=obj', '-O0', ir, '-o', obj], 'leak-witness-object', {0}); run(['cc', '-no-pie', obj, '-o', exe], 'leak-witness-link', {0}); run([exe], 'leak-witness-execute', {42}); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], 'leak-witness-memory', {99}); assert b'definitely lost: 8 bytes in 1 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr; row['raw_O0_memory_falsifier'] = 'Expected exit 42 but leaks the eight-byte input buffer; Valgrind exit 99'
		variants.append(row)
	(leaf/'result.json').write_text(json.dumps(dict(status='OWNER_FOCUSED_CONTROLS', target_profile=a.mode, component_sha256=sha(a.component), fixture_sha256=sha(source), semantic=[dict(category=c, stage=s, meaning=SEMANTIC[c]) for c, s in semantic], LLVM_valid_physical=variants, limitation='Static checked receiver, loop exits and throw-move Error controls remain additional requirements.'), indent=2)+'\n'); print(a.mode, '16 owner semantics and 8 LLVM-valid alternatives rejected', flush=True)


if __name__ == '__main__':
	main()
