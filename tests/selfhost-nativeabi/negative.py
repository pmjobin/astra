#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Producer-independent ABI/lifetime audits of real post-SSA corruptions."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-llvm'))
from oracle import memory

MUTATIONS = {
	21: 'forged-native-versus-C-plan', 22: 'wrong-floating-C-register-channel',
	23: 'unapproved-fast-math', 24: 'mixed-C-argument-register-order',
	25: 'wrong-record-layout-offset', 26: 'wrong-authoritative-field-index',
	27: 'replacement-retires-wrong-storage', 28: 'missing-replacement-free',
	29: 'unproved-C-pointer-alignment', 30: 'wrong-import-physical-symbol',
	31: 'wrong-export-native-target', 32: 'forged-hidden-result-convention',
	33: 'forged-module-type-cache', 34: 'wrong-FP-NaN-predicate',
	35: 'retired-owner-rearmed', 36: 'wrong-C-wrapper-calling-convention',
	37: 'wrong-floating-negation-operand',
}


def digest(data):
	return hashlib.sha256(data).hexdigest()


def main():
	resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
	p = argparse.ArgumentParser()
	for key in ('component', 'compiler', 'runtime', 'build', 'frozen', 'legacy'):
		p.add_argument('--'+key, type=Path, required=True)
	p.add_argument('--mode', choices=('O0', 'O2'), required=True)
	a = p.parse_args()
	assert all(not x.resolve().is_relative_to(ROOT) for x in (a.runtime, a.build))
	a.runtime.mkdir(parents=True, exist_ok=False); a.build.mkdir(parents=True, exist_ok=True)
	commands, mutants = [], []
	def run(argv, name, expected=0):
		start = time.monotonic()
		r = subprocess.run(['/usr/bin/time', '-v', '-o', str(a.runtime/(name+'.time')), *map(str, argv)], capture_output=True, cwd=a.build, timeout=300, env=dict(os.environ, CCACHE_DISABLE='1'))
		(a.runtime/(name+'.stdout')).write_bytes(r.stdout); (a.runtime/(name+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=name, argv=list(map(str, argv)), exit=r.returncode,
			monotonic_start=start, monotonic_end=time.monotonic()))
		(a.runtime/'commands.json').write_text(json.dumps(commands, indent=2)+'\n')
		assert r.returncode == expected, (name, r.returncode, r.stderr[-3000:].decode(errors='replace'))
		return r
	# This separate, executed baseline provides two genuine owner locations for
	# the replacement-storage fault. It is not counted in the selected corpus.
	source = a.runtime/'replacement-two-owners.astra'
	source.write_text('int main(){owned int[] a=new int[2];owned int[] b=new int[4];a=new int[3];return 0;}\n')
	obj = a.build/'replacement-two-owners.o'; native = a.build/'replacement-two-owners'; reference = native.with_suffix('.c0')
	run([a.component, '--emit-obj', a.mode, obj, source], 'owner-baseline-emit')
	run(['gcc', obj, '-o', native], 'owner-baseline-link')
	run([a.compiler, '-'+a.mode, source, '-o', reference], 'owner-baseline-C0')
	baseline_memory = {}
	for label, exe in [('native', native), ('C0', reference)]:
		run([exe], 'owner-baseline-'+label)
		v = run(['valgrind', '--default-suppressions=no', '--trace-malloc=yes', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', exe], 'owner-baseline-memory-'+label)
		baseline_memory[label] = memory(v.stderr, [('A', 2), ('A', 4), ('A', 3), ('F', 2), ('F', 4), ('F', 3)])
	assert baseline_memory['native']['observed_trace'] == baseline_memory['C0']['observed_trace']
	items = json.loads((a.frozen/'selection.json').read_text())
	legacy = json.loads((a.legacy/'selection.json').read_text())
	selected = {'fp32-call', 'fp64-branch', 'fp-unordered', 'c-mixed-pointer',
		'c-export-fp', 'c-borrowed-noescape', 'aggregate-nested-fp', 'owner-buffer-replace'}
	cases = [(x['name'], Path(x['source_path']), x['source_sha256']) for x in items if x['name'] in selected]
	cases += [(x['name'], Path(x['source_path']), x['source_sha256']) for x in legacy if x['name'] == 'ssa-owning-return']
	cases.append(('replacement-two-owners', source, digest(source.read_bytes())))
	killed = set()
	for name, path, sha in cases:
		assert digest(path.read_bytes()) == sha
		output = a.runtime/(name+'.forbidden.o')
		r = run([a.component, '--nativeabi-mutations', a.mode, output, path], name+'-mutations')
		assert not output.exists()
		for line in r.stdout.splitlines():
			x = line.split(); assert len(x) == 9 and x[0] == b'NATIVEABI_MUTATION', x[:3]
			category, stage = map(int, x[1:3]); assert category in MUTATIONS and stage in (1, 2, 3, 4)
			before_plan, before_ir, mutant_plan, mutant_ir, restored_plan, restored_ir = [bytes.fromhex(v.decode()) for v in x[3:]]
			assert (before_plan, before_ir) == (restored_plan, restored_ir)
			assert (before_plan, before_ir) != (mutant_plan, mutant_ir)
			killed.add(category)
			mutants.append(dict(case=name, source_sha256=sha, category=MUTATIONS[category], index=category,
				stage={1:'independent-ABI-plan-and-layout', 2:'independent-retirement', 3:'independent-source-IR-correspondence', 4:'LLVM-verifier'}[stage],
				before_plan_sha256=digest(before_plan), mutant_plan_sha256=digest(mutant_plan), restored_plan_sha256=digest(restored_plan),
				before_ir_sha256=digest(before_ir), mutant_ir_sha256=digest(mutant_ir), restored_ir_sha256=digest(restored_ir),
				seal_independent=True, upstream_backing_unchanged=True))
		(a.runtime/'mutants.json').write_text(json.dumps(mutants, indent=2)+'\n')
	assert killed == set(MUTATIONS), sorted(set(MUTATIONS)-killed)
	assert any(x['index'] == 27 and x['case'] == 'replacement-two-owners' for x in mutants)
	# Failed physical verification must preserve an existing destination.
	sentinel = a.runtime/'existing-destination.sentinel'; sentinel.write_bytes(b'original destination bytes\n')
	run([a.component, '--nativeabi-mutations', a.mode, sentinel, source], 'preserve-existing-destination')
	assert sentinel.read_bytes() == b'original destination bytes\n'
	memories = []
	for name in ('fp64-branch', 'c-borrowed-noescape', 'replacement-two-owners'):
		_, path, sha = next(x for x in cases if x[0] == name)
		v = run(['valgrind', '--default-suppressions=no', '--error-exitcode=97', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=definite,indirect,possible', a.component, '--nativeabi-mutations', a.mode, sentinel, path], name+'-mutation-memory')
		memories.append(dict(name=name, source_sha256=sha, memory=memory(v.stderr)))
		assert sentinel.read_bytes() == b'original destination bytes\n'
	(a.runtime/'result.json').write_text(json.dumps(dict(status='PASS', mode=a.mode, categories=len(killed),
		component_sha256=digest(a.component.read_bytes()), mutations=mutants,
		baseline_memory=baseline_memory, mutation_memory=memories,
		limits='Additional new physical faults; original 21 categories and upstream proofs remain separately mandatory.'), indent=2)+'\n')
	print(a.mode, len(killed), 'new independent mutation categories rejected')


if __name__ == '__main__':
	main()
