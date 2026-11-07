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


def expanded_corpus():
	rows = corpus()
	def observed(expression, message='kept', catches=None):
		if catches is None: catches = 'catch (Error error) { if (error.message == "'+message+'") return 42; return 4; }'
		return 'int main() { try { '+expression+' } '+catches+' }\n'
	leaf = 'int leaf(bool fail) throws Error { if (fail) { throw new Error("kept"); } return 17; }\n'
	rows['nested-direct-error'] = leaf+'int relay(bool fail) throws Error { return leaf(fail) + 1; }\n'+observed('return relay(true);')
	rows['nested-direct-success'] = leaf+'int relay(bool fail) throws Error { return leaf(fail) + 1; }\nint main() { try { return relay(false) + 24; } catch (Error error) { return 4; } }\n'
	rows['derived-exact-catch'] = 'int leaf() throws RuntimeError { throw new RuntimeError("kept"); }\n'+observed('return leaf();', catches='catch (RuntimeError derived) { if (derived.message == "kept") return 42; return 4; } catch (Error ancestor) { return 5; }')
	rows['derived-ancestor-catch'] = 'int leaf() throws RuntimeError { throw new RuntimeError("kept"); }\n'+observed('return leaf();')
	rows['ordered-root-catch'] = leaf+observed('return leaf(true);', catches='catch (RuntimeError derived) { return 5; } catch (Error ancestor) { if (ancestor.message == "kept") return 42; return 4; }')
	rows['bare-rethrow'] = leaf+'int relay(bool fail) throws Error { try { return leaf(fail); } catch (Error caught) { throw; } }\n'+observed('return relay(true);')
	rows['replacement-capture'] = leaf+'int relay(bool fail) throws Error { try { return leaf(fail); } catch (Error caught) { throw new Error(caught.message); } }\n'+observed('return relay(true);')
	rows['outer-handler'] = leaf+observed('try { return leaf(true); } catch (RuntimeError specific) { return 5; }')
	rows['empty-snapshot'] = 'int leaf() throws Error { throw new Error(""); }\n'+observed('return leaf();', message='')
	rows['nul-utf8-snapshot'] = 'int leaf() throws Error { throw new Error("é\\0x"); }\n'+observed('return leaf();', message='é\\0x')
	rows['nested-void-success'] = 'void leaf(bool fail) throws Error { if (fail) { throw new Error("kept"); } }\nvoid relay(bool fail) throws Error { leaf(fail); }\nint main() { try { relay(false); return 42; } catch (Error error) { return 4; } }\n'
	assert len(rows) == len(set(rows.values()))
	return rows


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--component', type=Path, required=True); p.add_argument('--version', required=True); p.add_argument('--without-message-read', action='store_true'); p.add_argument('--expanded', action='store_true'); a = p.parse_args(); assert a.version.isalnum(); assert not (a.expanded and a.without_message_read)
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
	for name, source in (expanded_corpus() if a.expanded else corpus(not a.without_message_read)).items():
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
			save()
			# An empty counted snapshot can use null backing storage. C0 uses
			# that representation and can remove the whole empty case at O2.
			# Its O0 twin retains the physical allocation witness.
			optimized_empty = a.mode == 'O2' and name == 'empty-snapshot'
			if not name.endswith('-success') and not optimized_empty: assert allocations >= (1 if name == 'empty-snapshot' else 2), 'The executed error path must allocate its Error and any nonempty snapshot'
			if name == 'replacement-capture': assert allocations == 4, 'Replacement must allocate its new owner before retiring the caught owner'
		row.update(Astra_effect_ELF=True, Astra_raw_LLVM_sha256=sha(ir), Astra_optimized_LLVM_sha256=sha(optimized), Astra_ELF_sha256=sha(exe), expected_exit=42, unsuppressed_Valgrind='Astra and independent C0: zero errors and live allocations'); save(); print(a.mode, name, 'Astra ELF and C0 oracle agree; LLVM and unsuppressed Valgrind pass', flush=True)


if __name__ == '__main__':
	main()
