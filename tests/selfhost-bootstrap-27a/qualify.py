#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Execute both actual compiler stages, C0 oracles and returning memory checks."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT/'tests/selfhost-compiler-complete'))
from run import C0_SHA256, WORK, sha
from acceleration import environment, execute, output_path, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('compiler', 'stage1', 'stage2', 'inputs', 'frontiers', 'build', 'runtime'): p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--version', required=True); a = p.parse_args()
	assert a.version.isalnum() and sha(a.compiler) == C0_SHA256
	leaf = output_path(a.runtime/a.version, WORK/'runtime'); build = output_path(a.build/a.version, WORK/'build')
	leaf.mkdir(); build.mkdir()
	link = json.loads((a.inputs/'link.json').read_text()); stages = dict(stage1=a.stage1, stage2=a.stage2)
	stage_hashes = {k:sha(v) for k, v in stages.items()}
	env = environment(dict(CCACHE_DISABLE='1', VALGRIND_OPTS=None, LD_PRELOAD=None, ASTRA_R4_FAIL_SIZE=None))
	commands = []; proofs = []
	def run(name, argv, expected=0, timeout=300):
		argv = list(map(str, argv)); result = execute(argv, leaf/name, expected=expected, timeout=timeout, env=env)
		commands.append(dict(name=name, argv=argv, executable_sha256=sha(argv[0]) if Path(argv[0]).is_file() else None, result=result))
		write(leaf/'commands.json', commands)
		assert result['status'] == 'EXPECTED_OUTCOME', (name, result)
		return (leaf/name/'stdout').read_bytes(), (leaf/name/'stderr').read_bytes()
	def memory(name, argv, expected=42):
		_, log = run(name, ['valgrind', '--default-suppressions=no', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all', *argv], expected, 900)
		assert all(marker in log for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)'))
	old = json.loads((a.frontiers/'result.json').read_text())
	selected = ['full-original-flow-number', 'builder-growth-snapshot', 'derived-error-owned-buffer', 'array-fixed-slice', 'counted-C-import', 'shared-replacement-error']
	cases = {row['name']:{v['path']:v['sha256'] for v in row['inputs']} for row in old['programs'] if row['name'] in selected}
	base_libs = [ROOT/'lib/astra/base/errors.astra']
	for n in ('record-arrays', 'checked-record-results'):
		paths = [ROOT/('tests/selfhost-compiler-complete/'+n+'.astra'), *base_libs]
		cases[n] = {str(v):sha(v) for v in paths}
	for n in ('caught-message-call', 'caught-message-scalars'):
		paths = [ROOT/('tests/selfhost-bootstrap-27a/'+n+'.astra'), *[Path(p) for p in json.loads((a.inputs/'inputs.json').read_text())['inputs'] if p.endswith(('/lib/astra/base/errors.astra', '/lib/astra/hosted/text.astra'))]]
		cases[n] = {str(v):sha(v) for v in paths}
	owned = ROOT/'tests/selfhost-bootstrap-27a/owned-borrowed-calls.astra'
	cases['owned-borrowed-calls'] = {str(owned):sha(owned)}
	# One independent known result and multifile cross-call, outside compiler data.
	small = build/'exit42.astra'; small.write_text('int main() { return 42; }\n')
	part = build/'multifile.astra'; part.write_text('int increment(int value) { return value + 1; }\n')
	entry = build/'entrée.astra'; entry.write_text('int main() { return increment(41); }\n')
	cases['exit42'] = {str(small):sha(small)}
	cases['UTF8-multifile'] = {str(entry):sha(entry), str(part):sha(part)}
	# All retained platform providers and the independently authored C oracle.
	prior_commands = json.loads((a.frontiers/'commands.json').read_text())
	prior_link = next(v['argv'] for v in prior_commands if v['name'] == 'full-original-flow-number-Astra-link')
	providers = [Path(v) for v in prior_link[prior_link.index('-no-pie')+2:prior_link.index('-o')]]
	assert all(v.is_file() for v in providers)
	for name, inputs in cases.items():
		assert all(sha(path) == h for path, h in inputs.items())
		oracle = build/(name+'-C0')
		links = [arg for path in providers for arg in ('--link-object', path)]
		run(name+'-C0-build', [a.compiler, '-O2', *inputs, *links, '-o', oracle])
		oracle_out = run(name+'-C0-run', [oracle], 42)
		ir_hashes = {}; products = {}
		for stage, producer in stages.items():
			label = name+'-'+stage; raw = build/(label+'.ll')
			run(label+'-emit', [producer, '--emit-llvm', '-o', raw, *inputs])
			ir_hashes[stage] = sha(raw)
			run(label+'-verify', ['opt', '-passes=verify', '-disable-output', raw])
			for mode in ('O0', 'O2'):
				stem = label+'-'+mode; ir = build/(stem+'.ll'); obj = build/(stem+'.o'); exe = build/stem
				run(stem+'-opt', ['opt', '-passes=default<'+mode+'>', '-S', raw, '-o', ir])
				run(stem+'-verify', ['opt', '-passes=verify', '-disable-output', ir])
				run(stem+'-object', ['llc', '-filetype=obj', '-'+mode, ir, '-o', obj])
				run(stem+'-link', ['cc', '-no-pie', obj, *providers, '-o', exe])
				assert run(stem+'-run', [exe], 42) == oracle_out
				memory(stem+'-memory', [exe])
				products[stem] = {str(v):sha(v) for v in (ir, obj, exe)}
				if name in ('record-arrays', 'UTF8-multifile'):
					direct = build/(stem+'-direct.o'); direct_exe = build/(stem+'-direct')
					run(stem+'-direct-object', [producer, '-c', '-'+mode, '-o', direct, *inputs])
					run(stem+'-direct-link', ['cc', '-no-pie', direct, *providers, '-o', direct_exe])
					assert run(stem+'-direct-run', [direct_exe], 42) == oracle_out
				if mode == 'O2' and name == 'record-arrays':
					memory(stem+'-compiler-memory', [producer, '--emit-llvm', '-o', raw, *inputs], 0)
			assert all(sha(path) == h for path, h in inputs.items())
		assert ir_hashes['stage1'] == ir_hashes['stage2'], (name, ir_hashes)
		proofs.append(dict(name=name, sources=inputs, raw_LLVM=ir_hashes, products=products, C0_oracle_sha256=sha(oracle), native_exit=42, strict_returning_memory=True))
		write(leaf/'programs.json', proofs); print('PROGRAM_PASS', name, flush=True)
	invalid = {
		'syntax':'int main( { return 42; }\n',
		'type':'int main() { bool value = 42; return 0; }\n',
		'type-UTF8':'// café\nint main() { bool value = 42; return 0; }\n',
		'borrow-transfer':'owned int[] bad(borrowed int[] values) { return move values; }\nint main() { return 0; }\n',
		'double-move':'class Item { init() {} }\nvoid consume(owned Item item) {}\nint main() { var item = new Item(); consume(move item); consume(move item); return 0; }\n',
		'unhandled-error':'void fail() throws Error { throw new Error("failed"); }\nint main() { fail(); return 42; }\n',
		'alias-overlap':'class Item { init() {} }\nvoid consume(borrowed Item view, owned Item item) {}\nint main() { var item = new Item(); consume(item, move item); return 0; }\n'}
	# C0 and the Astra compiler have independent diagnostic systems. Require
	# exact stage-specific refusals rather than pretending their messages match.
	refusals = {
		'syntax':('Typecore', b'expected parameter type name', b'expected parameter type name'),
		'type':('Typecore', b"expected initializer of type 'bool', found 'int'", b"expected initializer of type 'bool', found 'int'"),
		'type-UTF8':('Typecore', b"expected initializer of type 'bool', found 'int'", b"expected initializer of type 'bool', found 'int'"),
		'borrow-transfer':('Flow', b'astrac: Flow rejected this program\n', b"move source 'values' must be an owned void* local"),
		'double-move':('SSA', b'astrac: SSA verification failed\n', b"use of moved owned value 'item'"),
		'unhandled-error':('Typecore', b'checked error is neither caught nor within the declared throws bound', b"unhandled checked exception bound 'Error'"),
		'alias-overlap':('Flow', b'astrac: Flow rejected this program\n', b"cannot borrow moved owned value 'item'")}
	negatives = []
	for name, source in invalid.items():
		path = build/(name+'.astra'); path.write_text(source)
		inputs = [path, *base_libs]; _, oracle = run(name+'-C0-invalid', [a.compiler, '--check', *inputs], 1)
		phase, diagnostic, oracle_diagnostic = refusals[name]
		assert b'error:' in oracle and oracle_diagnostic in oracle
		observed = []
		for stage, producer in stages.items():
			destination = build/(name+'-'+stage+'.sentinel'); marker = b'UNCHANGED_27A_FAILURE_SENTINEL\n'; destination.write_bytes(marker)
			out, err = run(name+'-'+stage+'-invalid', [producer, '-o', destination, *inputs], 1)
			assert not out and destination.read_bytes() == marker
			assert not list(build.glob(destination.name+'.??????'))
			if phase == 'Typecore':
				match = re.fullmatch(re.escape(str(path).encode())+rb':(\d+):(\d+): error: '+re.escape(diagnostic)+rb'\n', err); assert match
			else:
				assert err == diagnostic
			observed.append(err)
			memory(name+'-'+stage+'-invalid-memory', [producer, '-o', destination, *inputs], 1)
			assert destination.read_bytes() == marker
		assert observed[0] == observed[1]
		span = None
		if phase == 'Typecore':
			match = re.search(rb':(\d+):(\d+): error: (.*)', observed[0]); assert match
			first, last = int(match[1]), int(match[2]); raw = path.read_bytes(); assert 0 <= first < last <= len(raw)
			position = re.search(rb':(\d+):(\d+): error: ', oracle); assert position
			line, column = int(position[1]), int(position[2])
			assert first == sum(len(v) for v in raw.splitlines(keepends=True)[:line-1])+column-1
			span = [first, last]
		negatives.append(dict(name=name, source_sha256=sha(path), diagnostic_sha256=__import__('hashlib').sha256(observed[0]).hexdigest(), rejection_phase=phase, byte_span=span, independent_C0_rejection=True, exact_stage_diagnostic=True, output_preserved=True, limitation='Flow/SSA refusals name the phase without a source span; Typecore diagnostics carry independently cross-checked byte positions.'))
	for stage, producer in stages.items():
		run(stage+'-version', [producer, '--version']); run(stage+'-help', [producer, '--help'])
		for name, args in [('unknown', ['--unsupported']), ('no-sources', []), ('missing-output', [small]), ('missing-file', ['-o', build/'missing.ll', build/'does-not-exist.astra']), ('same-path', ['-o', small, small]), ('duplicate', ['-o', build/'duplicate.ll', small, small])]:
			run(stage+'-'+name, [producer, *args], 1)
		assert small.read_text() == 'int main() { return 42; }\n'
		memory(stage+'-returning-error-memory', [producer, '--unsupported'], 1)
	assert stage_hashes == {k:sha(v) for k, v in stages.items()}
	write(leaf/'result.json', dict(status='STAGE1_AND_STAGE2_BEHAVIOR_ABI_MEMORY_VERIFIED', stages={k:dict(path=str(v), sha256=stage_hashes[k]) for k, v in stages.items()}, programs=proofs, independent_negative_controls=negatives, provider_objects={str(v):sha(v) for v in providers}, command_receipt_sha256=sha(leaf/'commands.json'), limitation='Focused current execution complements the separately retained historical campaigns. No release, syntax migration or final 27-D convergence qualification.'))
	print('STAGE1_AND_STAGE2_BEHAVIOR_ABI_MEMORY_VERIFIED', flush=True)


if __name__ == '__main__':
	main()
