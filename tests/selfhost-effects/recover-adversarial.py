#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Stage-specific controls and independently LLVM-valid body alternatives."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import time
from state import ROOT, C0, load_module, bounded_run, read, sha

FIXTURE = '''int leaf(bool fail) throws Error { if (fail) { throw new RuntimeError("kept"); } return 17; }
int relay(bool fail) throws Error { try { return leaf(fail); } catch (RuntimeError caught) { throw; } }
int main() { try { return relay(true); } catch (Error caught) { if (caught.message == "kept") return 42; return 4; } }
'''
SEMANTIC = ['projection result type', 'caught borrow origin', 'nominal message declaration', 'checked call handler coverage', 'lexical rethrow owner', 'catch borrow binding', 'conditional result channel', 'declared error channel', 'message owner lifetime', 'error edge interpreted as success', 'cleanup rank identity', 'typed dispatch inversion', 'rethrow allocation identity', 'success definition dominance', 'owned error phi channel', 'function owner routing', 'success value type']
PHYSICAL = ['false nullable-error branch', 'success-slot load on error', 'error return replaced with null', 'dynamic cleanup replaced with snapshot-only destructor', 'wrong descriptor parent', 'wrong dynamic destroy entry', 'original origin omitted', 'object free skipped', 'duplicate error cleanup', 'public checked channel']


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); a = p.parse_args(); assert a.version.isalnum()
	state = load_module('recover_mutation_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = state.RUNTIME/('adversarial-'+a.version+'-'+a.mode); build = state.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']; assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	path = leaf/'fixture.astra'; path.write_text(FIXTURE); inputs = [path, ROOT/'lib/astra/base/errors.astra']; commands = []
	def run(argv, label, allowed):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *argv], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=300)
		(leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=label, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(label+'.stdout')), stderr_sha256=sha(leaf/(label+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (label, r.returncode, r.stdout[-2000:], r.stderr[-2500:]); return r
	c0 = build/'C0'; run([C0, '-'+a.mode, *inputs, '-o', c0], 'C0-build', {0}); run([c0], 'C0-execute', {42})
	base = build/'positive.ll'; run([a.component, '--native', base, *inputs], 'positive-emit', {0}); run(['opt', '-passes=verify', '-disable-output', base], 'positive-verify', {0})
	positive_ir = build/'positive-optimized.ll'; run(['opt', '-passes=default<'+a.mode+'>', '-S', base, '-o', positive_ir], 'positive-optimize', {0}); positive_obj = build/'positive.o'; positive_exe = build/'positive'; run(['llc', '-filetype=obj', '-'+a.mode, positive_ir, '-o', positive_obj], 'positive-object', {0}); run(['cc', '-no-pie', positive_obj, '-o', positive_exe], 'positive-link', {0}); run([positive_exe], 'positive-execute', {42})
	positive_memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', positive_exe], 'positive-memory', {42}); assert b'ERROR SUMMARY: 0 errors' in positive_memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in positive_memory.stderr and b'(suppressed: 0 from 0)' in positive_memory.stderr
	r = run([a.component, '--adversarial', build, *inputs], 'Astra-stage-negatives', {0})
	semantic = [(int(c), int(s)) for c, s in re.findall(rb'RECOVER_SEMANTIC_REJECT ([0-9]+) ([0-9]+)', r.stdout)]; physical = [int(c) for c in re.findall(rb'RECOVER_LLVM_VALID_REJECT ([0-9]+)', r.stdout)]
	assert semantic == [(i, 1 if i <= 2 else 2 if i <= 5 else 3 if i <= 8 else 4 if i <= 12 else 5) for i in range(17)]
	assert physical == list(range(10)); results = []
	for category in physical:
		ir = build/('physical-'+str(category)+'.ll'); assert sha(ir) != sha(base), 'A physical alternative must actually change LLVM bytes'
		run(['llvm-as', ir, '-o', build/('physical-'+str(category)+'.bc')], 'physical-'+str(category)+'-assemble', {0}); run(['opt', '-passes=verify', '-disable-output', ir], 'physical-'+str(category)+'-verify', {0})
		optimized = build/('physical-'+str(category)+'-optimized.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', ir, '-o', optimized], 'physical-'+str(category)+'-optimize', {0}); run(['opt', '-passes=verify', '-disable-output', optimized], 'physical-'+str(category)+'-optimized-verify', {0})
		row = dict(category=category, meaning=PHYSICAL[category], LLVM_sha256=sha(ir), source_correspondence='Astra physical verifier rejected an LLVM-valid variant')
		if category == 7:
			obj = build/('physical-'+str(category)+'.o'); exe = build/('physical-'+str(category)); run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], 'physical-'+str(category)+'-object', {0}); run(['cc', '-no-pie', obj, '-o', exe], 'physical-'+str(category)+'-link', {0}); run([exe], 'physical-'+str(category)+'-execute', {42})
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], 'physical-'+str(category)+'-memory', {99}); assert b'definitely lost: 32 bytes in 1 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr; row['memory_falsification'] = 'Returns expected value but independently leaks the 32-byte error object'
		results.append(row)
	(leaf/'result.json').write_text(json.dumps(dict(status='FOCUSED_CONTROLS_ONLY', profile=a.mode, component_sha256=sha(a.component), fixture_sha256=sha(path), C0_ELF_sha256=sha(c0), semantic=[dict(category=c, stage=s, meaning=SEMANTIC[c]) for c, s in semantic], LLVM_valid_physical=results, limitation='Input-move reservation, owned success carriers and receiver controls remain additional requirements.'), indent=2)+'\n'); print(a.mode, '17 stage-specific controls and 10 LLVM-valid physical alternatives rejected', flush=True)


if __name__ == '__main__':
	main()
