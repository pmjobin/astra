#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Retain original failures and compare an explicitly named diagnostic derivative."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'tools/ci'))
from common import clean_environment, external, identify, require, run, sha, verify, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('llvm', 'original', 'candidate', 'receipt', 'ir', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	a = p.parse_args()
	require(sha(a.original) == '4b7e50c4ff5019fd21e817744eaad6a4c2ce8850e12dc4e6ab76672c7141cd36', 'original host library identity mismatch')
	receipt = json.loads(a.receipt.read_text())
	require(receipt['status'] == 'LLVM_INSTCOMBINE_DIAGNOSTIC_DERIVATIVE' and receipt['source_patch'] is None and receipt['public_distribution_approved'] is False, 'unexpected candidate')
	verify(a.candidate, receipt['library'])
	require(sha(a.ir) == '337d33653d87b5fac23fb4e68fcac73017188bb62111386dc26510e6a9e5bc34', 'original serialized values IR changed')
	build, runtime = external(a.build), external(a.runtime)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	env = clean_environment()
	oracle = build/'llvm-direct'
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-I'+str(a.llvm/'include'), ROOT/'tests/install/diagnostics/llvm-direct.c', a.original, '-o', oracle], runtime/'build-oracle', env)
	identity = build/'identity.ll'
	identity.write_text('define i32 @identity(i32 %a) {\n  ret i32 %a\n}\n')
	invalid = build/'invalid.ll'
	invalid.write_text('define i32 @invalid(i32 %a) {\n  ret i64 0\n}\n')
	vg = ['valgrind', '--default-suppressions=no', '--track-origins=yes', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all']
	cases = [('minimal', ROOT/'tests/install/diagnostics/llvm-instcombine.ll', 'function(instcombine)', 'none'), ('values', a.ir, 'default<O2>', 'native'), ('identity', identity, 'function(instcombine)', 'none'), ('invalid', invalid, 'function(instcombine)', 'none')]
	observations, outputs = [], {}
	for variant, library in [('original', a.original), ('rebuilt', a.candidate)]:
		# The selected loader path is part of each retained command, rather than
		# depending on an unrecorded ambient environment.
		prefix = ['env', 'LD_LIBRARY_PATH='+str(library.resolve().parent)]
		loaded, _ = run([*prefix, 'ldd', oracle], runtime/(variant+'-dependencies'), env)
		require(str(library.resolve()).encode() in loaded, 'oracle selected the wrong library')
		for name, source, pipeline, target in cases:
			label = variant+'-'+name
			out = build/(label+'.ll')
			expected = 1 if name == 'invalid' else 99 if variant == 'original' and name in ('minimal', 'values') else 0
			_, err = run([*prefix, *vg, oracle, source, pipeline, target, out], runtime/label, env, expected=expected)
			if expected == 99:
				require(b'foldUsingDistributiveLaws' in err and b'uninitialised' in err and b'in use at exit: 0 bytes in 0 blocks' in err, 'original optimizer failure did not reproduce')
			else:
				require(all(marker in err for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)')), 'strict oracle control failed')
			if name == 'invalid':
				require(not out.exists() and b'error:' in err, 'invalid IR did not refuse output')
			else:
				outputs[(variant, name)] = identify(out)
			observations.append(dict(label=label, expected_exit=expected, input=identify(source), command=identify(runtime/label/'command.json')))
	comparisons = {name:outputs[('original', name)]['sha256'] == outputs[('rebuilt', name)]['sha256'] for name in ('minimal', 'values', 'identity')}
	require(all(comparisons.values()), 'optimized IR changed; inspect outputs before further qualification')
	write(runtime/'result.json', dict(status='ORIGINAL_FAILURE_REPRODUCED_REBUILT_ORACLE_STRICT_CLEAN', original=identify(a.original), candidate=identify(a.candidate), candidate_receipt=identify(a.receipt), oracle=identify(oracle), source=identify(ROOT/'tests/install/diagnostics/llvm-direct.c'), observations=observations, optimized_IR_equal=comparisons, scope='Focused causal evidence only; original NOT_PASS retained. No suppressed errors, source patch, toolchain version replacement, final dependency approval, new installer or hosted/Windows qualification.'))
	print('ORACLE_COMPARISON_PASS_WITH_ORIGINAL_NOT_PASS_RETAINED')


if __name__ == '__main__':
	main()
