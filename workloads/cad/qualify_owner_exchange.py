#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""ASTRA-OWN-SWAP-1: retain I0 and materialize the minimal versioned I1."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
import qualify_idiomatic as accepted
from qualify import controls, suite

ROOT = Path(__file__).resolve().parents[2]
OLD = '\twhile (k < c.count) { var previous = c.state[k]; c.state[k] = c.next[k]; c.next[k] = previous; k = k + 1; }'
NEW = '\tswap(c.state, c.next);'
I0_SHA256 = 'c3a92710d107a6da9ec6d618dd40b54bf23c9f73e48e2b39124e9c17868b25b3'


def materialize(reference, output, exchange=True):
	original = accepted.idiomatic(reference, output)
	path = output / 'src/algorithm.astra'
	assert accepted.sha256(path) == I0_SHA256
	if exchange:
		text = path.read_text(); assert text.count(OLD) == 1
		path.write_text(text.replace(OLD, NEW))
	result = dict(route='I1' if exchange else 'I0', accepted_recipe_sha256=original['recipe_sha256'], members=accepted.members(output), rotation=dict(before=OLD, after=NEW if exchange else OLD))
	differences = [name for name in original['members'] if original['members'][name] != result['members'][name]]
	assert differences == (['src/algorithm.astra'] if exchange else [])
	return result


def build(args, out, route):
	source, target = out / (route + '-source'), out / (route + '-build')
	recipe = materialize(out / 'original', source, route == 'I1')
	accepted.write(out / (route + '-source.json'), recipe)
	accepted.execute(['meson', 'setup', target, source, '-Dwerror=true', '-Ddebug=false', '-Dastra_compiler=' + str(args.compiler.resolve()), '-Dargs_provider=' + str(args.args_provider.resolve()), '-Dreference_data=' + str(args.assets.resolve())], out, route + '-setup')
	accepted.execute(['meson', 'compile', '-C', target, '-j2'], out, route + '-build')
	return target


def main():
	parser = argparse.ArgumentParser(description=__doc__)
	for name in ['cad-repository', 'assets', 'compiler', 'args-provider', 'output']:
		parser.add_argument('--' + name, type=Path, required=True)
	parser.add_argument('--acceptance', action='store_true')
	args = parser.parse_args(); out = args.output.resolve()
	if not out.is_relative_to(ROOT / 'build/own-swap-1') or out == ROOT / 'build/own-swap-1':
		parser.error('output must be a fresh child of build/own-swap-1/')
	out.mkdir(parents=True, exist_ok=False)
	for directory in ['references', 'logs', 'tmp']:
		(out / directory).mkdir()
		# Reuse the accepted exact input/oracle checks, preserving its legacy reference
		# identities. The current candidate and accepted delivery are separate facts.
	record = accepted.preflight(args, out)
	if record['missing']:
		print(json.dumps(record)); return 2
	result = dict(status='INCOMPLETE', baseline='1a03559c60ca34b9cf46183e0bb0854352b05683', compiler_sha256=accepted.sha256(args.compiler), args_provider_sha256=accepted.sha256(args.args_provider))
	try:
		for route in ['I0', 'I1']:
			target = build(args, out, route)
			result[route] = {name: accepted.sha256(target / name) for name in ['astra-cad', 'numeric-tests', 'algorithm-tests', 'step-tests', 'orientation-tests', 'libcad-io.so', 'libcad-test-io.so']}
		if args.acceptance:
			accepted.execute(['meson', 'test', '-C', out / 'I1-build', '--no-rebuild', '--print-errorlogs', '-j2', '--timeout-multiplier=2'], out, 'I1-acceptance')
			result['suite'] = suite(out / 'I1-build', 13)
			result['controls'] = controls(out / 'I1-build', json.loads((out / 'references/ASTRA-CAD-2-VALIDATION.json').read_text()))
			result['status'] = 'I1_ORIGINAL_13_ENTRY_37_CONTROL_PASS'
		else:
			result['status'] = 'I0_I1_BUILT_NOT_QUALIFIED'
	finally:
		accepted.write(out / 'result.json', result)
	print(json.dumps(result)); return 0


if __name__ == '__main__':
	sys.exit(main())
