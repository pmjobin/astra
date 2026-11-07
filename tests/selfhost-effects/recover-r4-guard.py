#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Observe real field-root null guards, RHS order and distinct owner exchange."""
import argparse
import json
import os
from pathlib import Path
import re
import time
from state import ROOT, C0, load_module, read, sha, bounded_run


def corpus():
	prefix = 'class Box { int value; init() { this.value = 42; } } owned Box make(bool absent) { if (absent) return null; var value = new Box(); return move value; } int fail() throws Error { throw new Error("kept"); }\n'
	return {
		'null-field-load':prefix+'int main() { var value = make(true); return value.value; }\n',
		'nonnull-field-load':prefix+'int main() { var value = make(false); return value.value; }\n',
		'null-field-store-before-RHS':prefix+'int main() { var value = make(true); try { value.value = fail(); return 3; } catch (Error caught) { return 42; } }\n',
		'nonnull-field-store-RHS-error':prefix+'int main() { var value = make(false); try { value.value = fail(); return 3; } catch (Error caught) { if (caught.message != "kept") return 4; return value.value; } }\n',
		'nonnull-field-store-normal':prefix+'int main() { var value = make(false); value.value = 17; value.value = value.value + 25; return value.value; }\n',
		'distinct-receiver-buffer-exchange':'class Box { owned int[] data; init(owned int[] data) { this.data = move data; } } int main() { var first_data = new int[1]; var last_data = new int[42]; var first = new Box(move first_data); var last = new Box(move last_data); swap(first.data, last.data); if (len(last.data) != 1) return 3; return len(first.data); }\n',
		'constructor-argument-error-abort':'class Packet { private owned int[] data; private int tag; init(owned int[] data, int tag) { this.data = move data; this.tag = tag; } } int fail() throws Error { throw new Error("kept"); } int main() { var data = new int[7]; try { var result = new Packet(move data, fail()); return 3; } catch (Error caught) { if (caught.message != "kept") return 4; return 42; } }\n',
	}


def main():
	p = argparse.ArgumentParser(); p.add_argument('--mode', choices=('O0', 'O2'), required=True); p.add_argument('--version', required=True); p.add_argument('--component', type=Path); a = p.parse_args(); assert a.version.isalnum()
	paths = load_module('r4_guard_paths', ROOT/'tests/selfhost-effects/recover-build.py'); leaf = paths.RUNTIME/('r4-field-guard-'+a.version+'-'+a.mode); build = paths.BUILD/leaf.name; leaf.mkdir(); build.mkdir(); commands = []; rows = []
	if a.component:
		identity = read(a.component.with_suffix('.identity.json')); assert sha(a.component) == identity['sha256'] and all(sha(path) == expected for group in ('sources', 'tools') for path, expected in identity['identity'][group].items())
	def run(argv, name):
		argv = list(map(str, argv)); start = time.monotonic(); environment = dict(os.environ, CCACHE_DISABLE='1'); environment.pop('LD_PRELOAD', None); environment.pop('VALGRIND_OPTS', None); r = bounded_run(['/usr/bin/time', '-v', '-o', leaf/(name+'.time'), *argv], cwd=build, env=environment, capture_output=True, timeout=300); (leaf/(name+'.stdout')).write_bytes(r.stdout); (leaf/(name+'.stderr')).write_bytes(r.stderr); commands.append(dict(name=name, argv=argv, exit=r.returncode, start=start, end=time.monotonic(), stdout_sha256=sha(leaf/(name+'.stdout')), stderr_sha256=sha(leaf/(name+'.stderr')))); (leaf/'commands.json').write_text(json.dumps(commands, indent=2)+'\n'); return r
	for name, source_text in corpus().items():
		source = leaf/(name+'.astra'); source.write_text(source_text); inputs = [source, ROOT/'lib/astra/base/errors.astra']; row = dict(name=name, source_sha256=sha(source), observations={}); products = [('C0', build/(name+'-C0'))]
		assert run([C0, '-'+a.mode, *inputs, '-o', products[0][1]], name+'-C0-build').returncode == 0
		if a.component:
			ir = build/(name+'.ll'); optimized = build/(name+'-optimized.ll'); obj = build/(name+'.o'); native = build/(name+'-Astra'); assert run([a.component, '--native', ir, *inputs], name+'-emit').returncode == 0; assert run(['opt', '-passes=verify', '-disable-output', ir], name+'-verify').returncode == 0; assert run(['opt', '-passes=default<'+a.mode+'>', '-S', ir, '-o', optimized], name+'-optimize').returncode == 0; assert run(['opt', '-passes=verify', '-disable-output', optimized], name+'-optimized-verify').returncode == 0; assert run(['llc', '-filetype=obj', '-'+a.mode, optimized, '-o', obj], name+'-object').returncode == 0; assert run(['cc', '-no-pie', obj, '-o', native], name+'-link').returncode == 0; products.append(('Astra', native)); row['raw_LLVM_sha256'] = sha(ir)
		for label, product in products:
			execution = run([product], name+'-'+label+'-execute'); signal = re.search(r'Command terminated by signal ([0-9]+)', (leaf/(name+'-'+label+'-execute.time')).read_text()); result = -int(signal[1]) if signal else execution.returncode; assert result in (42, -4); observation = dict(actual_exit=result, ELF_sha256=sha(product), returning_memory=None)
			if result == 42:
				memory = run(['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', product], name+'-'+label+'-memory'); assert memory.returncode == 42 and b'ERROR SUMMARY: 0 errors' in memory.stderr and b'in use at exit: 0 bytes in 0 blocks' in memory.stderr and b'(suppressed: 0 from 0)' in memory.stderr; observation['returning_memory'] = 'zero unsuppressed errors/live allocations'
			row['observations'][label] = observation
		if a.component: assert row['observations']['C0']['actual_exit'] == row['observations']['Astra']['actual_exit'], row
		rows.append(row); (leaf/'result.json').write_text(json.dumps(dict(status='C0_FIELD_GUARD_CONTROLS' if not a.component else 'INDEPENDENT_FIELD_GUARD_CONTROLS', profile=a.mode, component_sha256=sha(a.component) if a.component else None, programs=rows, primary_native_credit=0, limitation='Every fatal outcome is attributed independently and has no returning Valgrind credit. Guard timing is compared with actual C0 behavior; a caught RHS error cannot stand in for a fatal null receiver.'), indent=2)+'\n'); print(a.mode, name, {key:value['actual_exit'] for key, value in row['observations'].items()}, flush=True)


if __name__ == '__main__':
	main()
