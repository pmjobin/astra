#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Probe an actual compiler source interface against unchanged C0 native units."""
import argparse
import ast
import json
from pathlib import Path
import subprocess
import sys

from run import ROOT, WORK, C0_SHA256, sha, declarations
from acceleration import execute, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	p.add_argument('--compiler', type=Path, required=True)
	p.add_argument('--runtime-root', type=Path, required=True)
	p.add_argument('--build-root', type=Path, required=True)
	p.add_argument('--version', required=True)
	args = p.parse_args(); assert args.version.isalnum() and sha(args.compiler) == C0_SHA256
	leaf = args.runtime_root/('native-boundaries-'+args.version); build = args.build_root/leaf.name
	assert leaf.resolve().is_relative_to((WORK/'runtime').resolve()) and build.resolve().is_relative_to((WORK/'build').resolve())
	leaf.mkdir(); build.mkdir(); sources = []; inventory = []
	subprocess.run([sys.executable, '-B', ROOT/'tests/selfhost-compiler-complete/toolchain.py', '--compiler', args.compiler, '--receipt', leaf/'toolchain.json'], check=True)
	model = ast.parse((ROOT/'tests/selfhost-typecore/build.py').read_text())
	libraries = next(ast.literal_eval(node.value) for node in model.body if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == 'LIBRARIES' for target in node.targets))
	names = ['lib/astra/'+name+'.astra' for name in libraries]+['compiler/source/source.astra']
	for index, name in enumerate(names):
		original = ROOT/name; raw = original.read_bytes(); target = leaf/(str(index)+'-'+original.name)
		prefix = b'namespace CompilerBoundary26;\n'
		target.write_bytes(prefix+raw); target.chmod(0o444); sources.append(target)
		assert target.read_bytes()[len(prefix):] == raw
		inventory.append(dict(original=str(original), original_sha256=sha(original), prepared=str(target), prepared_sha256=sha(target), transformation='One namespace directive; every original source byte retained. Development interface probe only.'))
		old = execute([args.compiler, '--dump-syntax', original], leaf/(str(index)+'-original-AST'), timeout=60)
		new = execute([args.compiler, '--dump-syntax', target], leaf/(str(index)+'-prepared-AST'), timeout=60)
		assert old['exit'] == new['exit'] == 0
		original_declarations = declarations((leaf/(str(index)+'-original-AST')/'stdout').read_text())
		prepared_text = (leaf/(str(index)+'-prepared-AST')/'stdout').read_text()
		# The parser synthesizes these two factory constructor targets from the
		# declared namespace. Original authored bytes still match exactly above.
		for intrinsic_type in ('Utf8Message', 'InvalidUtf8'):
			prepared_text = prepared_text.replace('(new-object CompilerBoundary26.'+intrinsic_type, '(new-object '+intrinsic_type)
		prepared_declarations = declarations(prepared_text)
		assert all(prepared_declarations.count(row) >= original_declarations.count(row) for row in original_declarations)
	positive = execute([args.compiler, '--dump-semantics', *sources], leaf/'semantic-positive', timeout=300)
	assert positive['exit'] == 0, (leaf/'semantic-positive/stderr').read_text()
	selectors = ['Error', 'RuntimeError', 'Utf8Message', 'InvalidUtf8', 'Utf8ByteBuilder', 'SourceBoundsError', 'SourceLocation', 'SourceBuffer', 'SourceSpan', 'SourceDiagnostic', 'TextRangeError', 'IntegerParseError', 'TextCapacityError']
	observations = []
	for mode in ('O0', 'O2'):
		interface = build/(mode+'.asti'); obj = build/(mode+'.o')
		command = [args.compiler, '-'+mode, '-c', '--module', 'CompilerBoundary26', '--emit-interface', interface, *[part for selector in selectors for part in ('--native-export', 'CompilerBoundary26.'+selector)], *sources, '-o', obj]
		result = execute(command, leaf/mode, timeout=300)
		stderr = (leaf/mode/'stderr').read_text()
		observations.append(dict(mode=mode, actual_exit=result['exit'], timed_out=result['timed_out'], stderr=stderr, object_created=obj.exists(), interface_created=interface.exists(), source_semantic_positive=True))
		assert not result['timed_out']
		if result['exit'] != 0:
			assert not obj.exists() and not interface.exists()
			assert 'native module:' in stderr and 'internal error' not in stderr.lower()
	assert all(sha(row['original']) == row['original_sha256'] for row in inventory)
	status = 'COMPILER_INTERFACE_NATIVE_UNIT_ADMITTED' if all(row['actual_exit'] == 0 for row in observations) else 'COMPILER_INTERFACE_NATIVE_UNIT_REFUSED'
	write(leaf/'result.json', dict(status=status, compiler_sha256=sha(args.compiler), source_inventory=inventory, observations=observations, parser_projection='Only the two synthesized Utf8MessageFactory constructor targets receive the declared namespace qualification; comparison removes that exact added qualification. Authored source bytes are retained verbatim.', full_original_native_credit=0, limitation='Actual SourceBuffer/SourceSpan/Error/text APIs with whole-file namespace preparation and explicit parser projection. A refusal applies to this proposed existing-API boundary; it is not a proof that every possible redesign is impossible. Scalar incremental units are a separate working mechanism. Original C0, sources and public ABI remain unchanged.'))
	print(status, leaf, flush=True)


if __name__ == '__main__':
	main()
