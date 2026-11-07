#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Early genuine Astra effects, with separate C0 and native tool evidence."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import time
from state import ROOT, C0, load_module, bounded_run, sha, read


def corpus(message_read=True):
	rows = {}
	for shape in ('void', 'scalar'):
		result = 'void' if shape == 'void' else 'int'; value = '' if shape == 'void' else ' 17'
		leaf = result+' leaf(bool fail) throws Error { if (fail) { throw new Error("E25-A"); } return'+value+'; }\n'
		for fail in (False, True):
			call = 'leaf('+str(fail).lower()+')'
			body = call+'; return '+('3' if fail else '42')+';' if shape == 'void' else 'return '+call+('' if fail else ' + 25')+';'
			catch = ('if (error.message == "E25-A") return 42; return 3;' if message_read else 'return 42;') if fail else 'return 3;'
			rows[shape+('-error' if fail else '-success')] = leaf+'int main() { try { '+body+' } catch (Error error) { '+catch+' } }\n'
	return rows


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); p.add_argument('--without-message-read', action='store_true'); a = p.parse_args(); assert a.version.isalnum()
	state = load_module('recover_paths', ROOT/'tests/selfhost-effects/recover-build.py')
	leaf = state.RUNTIME/('early-'+a.version+'-'+a.mode); build = state.BUILD/leaf.name; leaf.mkdir(); build.mkdir()
	identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256']
	assert all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	commands = []; results = []; tools = {name:dict(path=shutil.which(name), sha256=sha(shutil.which(name))) for name in ('llvm-as', 'opt', 'llc', 'cc', 'valgrind')}
	def save():
		(leaf/'result.json').write_text(json.dumps(dict(status='PARTIAL', phase='Early scalar/void runtime evidence; full milestone gates remain required', message_read=not a.without_message_read, target_profile=a.mode, component_build_profile=identity['identity']['argv'][1], component_sha256=sha(a.component), commands=commands, programs=results, tools=tools, new_Astra_effect_ELFs=sum(row.get('Astra_effect_ELF', False) for row in results)), indent=2)+'\n')
	def run(argv, label, allowed):
		argv = list(map(str, argv)); start = time.monotonic(); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(label+'.time'), *argv], cwd=build, capture_output=True, env=dict(os.environ, CCACHE_DISABLE='1'), timeout=300)
		(leaf/(label+'.stdout')).write_bytes(r.stdout); (leaf/(label+'.stderr')).write_bytes(r.stderr)
		commands.append(dict(name=label, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(label+'.stdout')), stderr_sha256=sha(leaf/(label+'.stderr')))); save()
		assert r.returncode in allowed, (label, r.returncode, r.stdout[-2500:], r.stderr[-2500:]); return r
	for name, source in corpus(not a.without_message_read).items():
		path = leaf/(name+'.astra'); path.write_text(source); inputs = [path, ROOT/'lib/astra/base/errors.astra']; row = dict(name=name, source_sha256=sha(path), Astra_effect_ELF=False); results.append(row); save()
		c0 = build/(name+'-C0'); run([C0, '-'+a.mode, *inputs, '-o', c0], name+'-C0-build', {0}); run([c0], name+'-C0-execute', {42}); row['C0_ELF_sha256'] = sha(c0)
		oracle = run([C0, '-O0', '--dump-llvm', *inputs], name+'-C0-ABI', {0}); c0_ir = build/(name+'-C0.ll'); c0_ir.write_bytes(oracle.stdout); run(['opt', '-passes=verify', '-disable-output', c0_ir], name+'-C0-verify', {0})
		ir = build/(name+'-Astra.ll'); ir.write_text('Astra continuation output sentinel\n'); row['destination_before'] = sha(ir)
		run([a.component, '--native', ir, *inputs], name+'-Astra-emit', {0}); assert sha(ir) != row['destination_before']
		run(['llvm-as', ir, '-o', build/(name+'.bc')], name+'-Astra-assemble', {0}); run(['opt', '-passes=verify', '-disable-output', ir], name+'-Astra-verify', {0})
		optimized = build/(name+'-'+a.mode+'.ll'); run(['opt', '-passes=default<'+a.mode+'>', '-S', ir, '-o', optimized], name+'-Astra-optimize', {0}); run(['opt', '-passes=verify', '-disable-output', optimized], name+'-Astra-optimized-verify', {0})
		obj = build/(name+'.o'); run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], name+'-Astra-object', {0})
		exe = build/(name+'-Astra'); run(['cc', '-no-pie', obj, '-o', exe], name+'-Astra-link', {0}); run([exe], name+'-Astra-execute', {42})
		for compiler, program in (('Astra', exe), ('C0', c0)):
			memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', program], name+'-'+compiler+'-memory', {42})
			assert b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr
			heap = re.search(rb'total heap usage: ([0-9,]+) allocs, ([0-9,]+) frees', memory.stderr); assert heap
			allocations = int(heap[1].replace(b',', b'')); frees = int(heap[2].replace(b',', b'')); assert allocations == frees
			row[compiler+'_allocations'] = allocations
			if name.endswith('-error'): assert allocations >= 2, 'Error object and snapshot must actually allocate on the executed error path'
		row.update(Astra_effect_ELF=True, Astra_raw_LLVM_sha256=sha(ir), Astra_optimized_LLVM_sha256=sha(optimized), Astra_ELF_sha256=sha(exe), expected_exit=42, unsuppressed_Valgrind='Astra and independent C0: zero errors and live allocations'); save(); print(a.mode, name, 'Astra ELF and C0 oracle agree; LLVM and unsuppressed Valgrind pass', flush=True)


if __name__ == '__main__':
	main()
