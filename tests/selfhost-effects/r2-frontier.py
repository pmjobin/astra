#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Attempt the earliest void/scalar error ELFs; distinguish C0 from Astra."""
import argparse
import hashlib
import json
from pathlib import Path
import time
from state import ROOT, C0, bounded_run, sha, read, load_module


def corpus():
	rows = {}
	for shape in ('void', 'scalar'):
		result = 'void' if shape == 'void' else 'int'
		value = '' if shape == 'void' else ' 42'
		leaf = result+' leaf(bool fail) throws Error { if (fail) { throw new Error("E25-A"); } return'+value+'; }\n'
		for fail in (False, True):
			call = 'leaf('+str(fail).lower()+')'
			body = call+'; return 42;' if shape == 'void' else 'return '+call+';'
			catch = 'if (error.message == "E25-A") return 42; return 3;' if fail else 'return 3;'
			rows[shape+('-error' if fail else '-success')] = leaf+'int main() { try { '+body+' } catch (Error error) { '+catch+' } }\n'
	return rows


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--phase', choices=('baseline', 'final'), default='final'); p.add_argument('--attempt', default='v1'); a = p.parse_args(); assert a.attempt.isalnum()
	state = load_module('r2_frontier_state', ROOT/'tests/selfhost-effects/r2-state.py')
	leaf = state.RUNTIME/('frontier-'+a.phase+'-'+a.mode+'-'+a.attempt); build = state.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	commands = []; results = []
	def run(argv, label, allowed):
		start = time.monotonic(); argv = list(map(str, argv))
		r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *argv], cwd=build, capture_output=True, timeout=180)
		(leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=label, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(label+'.stdout')), stderr_sha256=sha(leaf/(label+'.stderr'))))
		(leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); assert r.returncode in allowed, (label, r.returncode, r.stderr[-2500:]); return r
	for name, source in corpus().items():
		path = leaf/(name+'.astra'); path.write_text(source); inputs = [path, ROOT/'lib/astra/base/errors.astra']
		exe = build/(name+'-C0'); run([C0, '-'+a.mode, *inputs, '-o', exe], name+'-C0-build', {0}); run([exe], name+'-C0-execute', {42})
		memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', exe], name+'-C0-memory', {42})
		assert b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
		ir = run([C0, '-O0', '--dump-llvm', *inputs], name+'-C0-ABI', {0}).stdout; irpath = build/(name+'-C0.ll'); irpath.write_bytes(ir)
		run(['llvm-as', irpath, '-o', build/(name+'-C0.bc')], name+'-C0-assemble', {0}); run(['opt', '-passes=verify', '-disable-output', irpath], name+'-C0-verify', {0})
		definitions = [s.decode() for s in ir.splitlines() if s.startswith(b'define internal fastcc ptr ')]
		assert len(definitions) == 1, definitions
		assert ('%success.storage' in definitions[0]) == name.startswith('scalar')
		target = build/(name+'-Astra.ll'); target.write_bytes(b'R2 native frontier destination sentinel\n'); before = sha(target)
		native = run([a.component, '--classstorage-llvm-raw', a.mode, target, *inputs], name+'-Astra-native', {1, 2, 3})
		assert sha(target) == before and b'LLVM_INVALID_UPSTREAM' in native.stderr
		trace = run([a.component, '--effects-trace', a.mode, leaf/'unused', *inputs], name+'-Astra-Flow', {0})
		rows = [line for line in trace.stdout.decode().splitlines() if line.startswith(('STATUS ', 'DEFER ', 'FLOW_VERIFY_STOP ', 'OBLIGATION ', 'PENDING ', 'SIGNATURE ', 'SOURCE_SIGNATURE '))]
		results.append(dict(name=name, source_sha256=sha(path), C0_native_sha256=sha(exe), C0_exit=42, C0_unsuppressed_memory='zero errors and live allocations', C0_checked_entry=definitions[0], C0_ABI_IR_sha256=sha(irpath), Astra_native_exit=native.returncode, Astra_destination_preserved=True, Astra_effect_ELF=False, Flow_observations=rows))
		(leaf/'result.json').write_text(json.dumps(dict(status='PARTIAL', component_sha256=sha(a.component), programs=results, new_Astra_effect_ELFs=0, C0_only_ELFs=len(results), first_boundary='Core 3 refuses incomplete Flow (STATUS 3 2): global Error/RuntimeError TYPE_POLICY 7; constructor MEMBER_POLICY 18 and UNSUPPORTED_EFFECT 6; throw/try syntax and throws flag 64 also defer. No owned error allocation, checked-call error successor, or success-only SSA definition is admitted. Signature fixtures are separate.'), indent=2)+'\n')
		print(a.mode, name, 'C0 native/memory/ABI pass; genuine Astra emission refused upstream', flush=True)


if __name__ == '__main__':
	main()
