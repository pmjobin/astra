#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Independent loop exits, Error slots, null guards and physical alternatives."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, bounded_run, read, sha

FIXTURE = '''owned Error make() { var value = new Error("kept"); return move value; }
int main() { var spare = new Error("spare"); int count = 0; while (count < 2) { var inner = new int[3]; while (true) { var nested = new int[2]; break; } count = count + 1; try { var value = make(); throw move value; } catch (Error caught) { if (caught.message != "kept") return 4; continue; } } return count + 40; }
'''
SEMANTIC = ['continue loses lexical loop identity', 'Error move loses actual owner slot', 'continue uses break destination', 'throw-move null guard reversed', 'raised Error SSA owner erased', 'Error result ownership qualifier erased']
PHYSICAL = ['owned Error backing cleanup skipped', 'throw-move normal and fatal targets swapped', 'throw-move guard checks a substituted null pointer', 'mutable loop store publishes zero', 'continue jumps to loop exit', 'nullable Error cleanup skips the live dynamic destructor']


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('loop_negative_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('loop-adversarial-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']; assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	source = leaf/'fixture.astra'; source.write_text(FIXTURE); inputs = [source, ROOT/'lib/astra/base/errors.astra']; commands = []
	def run(argv, name, allowed):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=300)
		(leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (name, r.returncode, r.stdout[-2000:], r.stderr[-3000:]); return r
	c0 = build/'C0'; run([C0, '-'+a.mode, *inputs, '-o', c0], 'C0-build', {0}); run([c0], 'C0-execute', {42})
	base = build/'positive.ll'; run([a.component, '--native', base, *inputs], 'positive-emit', {0}); run(['opt', '-passes=verify', '-disable-output', base], 'positive-verify', {0}); optimized = build/'positive-optimized.ll'; run(['opt', '-passes=default<'+a.mode+'>', '-S', base, '-o', optimized], 'positive-optimize', {0}); run(['opt', '-passes=verify', '-disable-output', optimized], 'positive-optimized-verify', {0}); obj = build/'positive.o'; exe = build/'positive'; run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], 'positive-object', {0}); run(['cc', '-no-pie', obj, '-o', exe], 'positive-link', {0}); run([exe], 'positive-execute', {42})
	for label, program in [('Astra', exe), ('C0', c0)]:
		memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', program], label+'-memory', {42}); assert b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
	r = run([a.component, '--loop-adversarial', build, *inputs], 'stage-negatives', {0}); semantic = [(int(c), int(s)) for c, s in re.findall(rb'RECOVER_LOOP_REJECT ([0-9]+) ([0-9]+)', r.stdout)]; physical = [int(c) for c in re.findall(rb'RECOVER_LOOP_LLVM_REJECT ([0-9]+)', r.stdout)]; assert semantic == list(enumerate([2, 3, 4, 4, 5, 6])) and physical == list(range(6)); variants = []
	for category in physical:
		ir = build/('loop-physical-'+str(category)+'.ll'); assert sha(ir) != sha(base); run(['llvm-as', ir, '-o', build/('loop-'+str(category)+'.bc')], 'physical-'+str(category)+'-assemble', {0}); run(['opt', '-passes=verify', '-disable-output', ir], 'physical-'+str(category)+'-verify', {0}); target = build/('loop-'+str(category)+'-optimized.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', ir, '-o', target], 'physical-'+str(category)+'-optimize', {0}); run(['opt', '-passes=verify', '-disable-output', target], 'physical-'+str(category)+'-optimized-verify', {0})
		row = dict(category=category, meaning=PHYSICAL[category], LLVM_sha256=sha(ir), semantic_rejection='Actual Astra physical verifier rejected an LLVM-valid variant')
		if category == 0:
			# Keep this raw O0 leak witness separate from the target-profile IR.
			obj = build/'leak-witness.o'; exe = build/'leak-witness'; run(['llc', '-filetype=obj', '-O0', ir, '-o', obj], 'leak-witness-object', {0}); run(['cc', '-no-pie', obj, '-o', exe], 'leak-witness-link', {0}); run([exe], 'leak-witness-execute', {42}); memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], 'leak-witness-memory', {99}); assert b'definitely lost: 32 bytes in 1 blocks' in memory.stderr and b'indirectly lost: 6 bytes in 1 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr; row['raw_O0_memory_falsifier'] = 'Expected exit 42 but leaks the ordinary owned Error and its snapshot; Valgrind exit 99'
		variants.append(row)
	(leaf/'result.json').write_text(json.dumps(dict(status='LOOP_ERROR_OWNER_CONTROLS', target_profile=a.mode, component_sha256=sha(a.component), fixture_sha256=sha(source), semantic=[dict(category=c, stage=s, meaning=SEMANTIC[c]) for c, s in semantic], LLVM_valid_physical=variants, limitation='Static checked receivers and original compiler-source execution require separate evidence.'), indent=2)+'\n'); print(a.mode, '6 loop/Error semantics and 6 LLVM-valid alternatives rejected', flush=True)


if __name__ == '__main__':
	main()
