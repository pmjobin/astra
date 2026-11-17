#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Compare historical installed payloads with an explicitly isolated LLVM rebuild."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'tools/ci'))
from common import clean_environment, external, identify, require, run, sha, verify, write


def main():
	p = argparse.ArgumentParser(description=__doc__)
	for name in ('package', 'llvm', 'library', 'receipt', 'build', 'runtime'):
		p.add_argument('--'+name, type=Path, required=True)
	p.add_argument('--kind', choices=('deb', 'rpm'), required=True)
	a = p.parse_args()
	pins = {'deb':'8c260da73471814caf780a604d74b3af454a4526dcb0dbe3dc635fcc1bff5386', 'rpm':'2207c00cba71651ef9e1cedbcc45c3a9f919dffcddc48de909b4a894ea6d5869'}
	require(sha(a.package) == pins[a.kind], 'historical installer identity mismatch')
	receipt = json.loads(a.receipt.read_text())
	require(receipt['status'] == 'LLVM_INSTCOMBINE_DIAGNOSTIC_DERIVATIVE' and receipt['public_distribution_approved'] is False and receipt['source_patch'] is None, 'unexpected diagnostic derivative')
	verify(a.library, receipt['library'])
	build, runtime = external(a.build), external(a.runtime)
	(runtime/'executed-recipe.py.txt').write_bytes(Path(__file__).read_bytes())
	env = clean_environment()
	install = ['dpkg', '-i', a.package] if a.kind == 'deb' else ['dnf', 'install', '-y', '--disablerepo=*', a.package]
	run(install, runtime/'install-historical', env)
	compiler = Path('/usr/lib/astra/astrac.native')
	original_library = Path('/usr/lib/astra/llvm/libLLVM.so.23.1')
	run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-I'+str(a.llvm/'include'), ROOT/'tests/install/diagnostics/llvm-direct.c', original_library, '-o', build/'llvm-direct'], runtime/'oracle-build', env)
	vg = ['valgrind', '--default-suppressions=no', '--track-origins=yes', '--error-exitcode=99', '--leak-check=full', '--show-leak-kinds=all', '--errors-for-leak-kinds=all']
	inputs = ROOT/'tests/install/diagnostics/llvm-instcombine.ll'
	baseline = dict(env, LD_LIBRARY_PATH=str(original_library.parent))
	_, err = run([*vg, build/'llvm-direct', inputs, 'function(instcombine)', 'none', build/'original.ll'], runtime/'original-oracle', baseline, expected=99)
	require(b'foldUsingDistributiveLaws' in err and b'uninitialised' in err and b'in use at exit: 0 bytes in 0 blocks' in err, 'original failure did not reproduce')
	_, err = run([*vg, compiler, '-c', '-O2', '-o', build/'original-values.o', '/usr/share/astra/tutorial/tests/books/values.astra'], runtime/'original-values', baseline, expected=99)
	require(b'foldUsingDistributiveLaws' in err and b'uninitialised' in err, 'installed compiler did not reproduce original failure')
	candidate = dict(env, LD_LIBRARY_PATH=str(a.library.resolve().parent))
	def strict(label, argv, expected=0):
		out, err = run([*vg, *argv], runtime/label, candidate, expected=expected)
		require(all(marker in err for marker in (b'ERROR SUMMARY: 0 errors', b'in use at exit: 0 bytes in 0 blocks', b'(suppressed: 0 from 0)')), 'strict memory failed: '+label)
		return out
	strict('rebuilt-oracle', [build/'llvm-direct', inputs, 'function(instcombine)', 'none', build/'rebuilt.ll'])
	lazy = build/'lazy-8.astra'
	lazy.write_text('language astra27b;\nint main() { var plan = (0..1)'+'.map(value => value+1)'*8+'; if (plan.sum() != 8) return 1; return 42; }\n')
	for name, source in [('values', Path('/usr/share/astra/tutorial/tests/books/values.astra')), ('lazy-8', lazy)]:
		for mode in ('O0', 'O2'):
			label = name+'-'+mode
			obj, exe = build/(label+'.o'), build/label
			strict(label+'-compile', [compiler, '-c', '-'+mode, '-o', obj, source])
			run(['cc', '-no-pie', obj, '-o', exe], runtime/(label+'-link'), candidate)
			require(strict(label+'-execute', [exe], expected=42) == b'', 'unexpected native output')
	write(runtime/'result.json', dict(status='HISTORICAL_INSTALLED_PAYLOAD_WITH_ISOLATED_LLVM_REBUILD_FOCUSED_PASS', package=identify(a.package), original_compiler=identify(compiler), original_library=identify(original_library), candidate_library=identify(a.library), derivative_receipt=identify(a.receipt), os_release=Path('/etc/os-release').read_text(), scope='Original installed package is unchanged. LD_LIBRARY_PATH explicitly selects the separate diagnostic rebuild for the C oracle and values/lazy-8 O0/O2 native and strict-memory tests. Shared host kernel; this is not a new installer, final package qualification, Windows execution or approval to distribute the derivative.'))
	print('FOCUSED_USERLAND_DIAGNOSTIC_PASS')


if __name__ == '__main__':
	main()
