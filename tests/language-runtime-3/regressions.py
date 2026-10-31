# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Proportional retained acceptance refresh; no exhaustive historic literal rerun."""
from pathlib import Path
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
NAMES = '''
wide-values wide-values-ubsan wide-ssa-verifier wide-llvm-verifier wide-public-execution
cabi-buffer-standalone cabi-buffer-pipeline cabi-buffer-provider cabi-buffer-qualification
modules-1-scopes-execution compiler-systems-2-optimizer-contracts
compiler-systems-2-applications compiler-systems-2-predecessor-public-O2
application-runtime-1-contracts application-runtime-1-execution
text-own-1a-contracts text-own-1a-native-execution
gen-member-1a-contracts gen-member-1a-native-execution gen-member-1a-source-refusals
gen-borrow-1-contracts gen-borrow-1-native-execution gen-borrow-1-negative
gen-own-2d-contracts gen-own-2d-native-execution gen-own-2d-negative
container-1a-contracts container-1a-native-execution container-1a-source-refusals
obj-field-2-stage-contracts obj-field-2-native-execution
obj-alloc-1-loan-contracts obj-alloc-1-native-execution
struct-move-1-stage-contracts struct-move-1-native-execution
error-1-snapshot error-1-heap error-1-native-execution
own-swap-core own-swap-cfg own-swap-ssa own-swap-llvm
prop-parser prop-semantic prop-pipeline prop-native-execution
lazy-1-contracts lazy-1-native-execution
async-1-runtime-protocol async-1-native-frames async-1-source-frame-execution
callable-native-standalone callable-model-and-lifetime callable-generated-native
ints-native-execution f32-native-execution f64-native-execution
sources-negative-provenance
'''.split()


def main(build):
	build = Path(build).resolve()
	assert not build.is_relative_to(ROOT)
	info = build/'meson-info'
	assert Path(json.loads((info/'meson-info.json').read_text())['directories']['source']).resolve() == ROOT
	subprocess.run(['meson', 'setup', '--reconfigure', str(build), str(ROOT)], check=True)
	tests = {entry['name']: entry for entry in json.loads((info/'intro-tests.json').read_text())}
	targets = {entry['id']: entry for entry in json.loads((info/'intro-targets.json').read_text())}
	assert len(NAMES) == len(set(NAMES)) and set(NAMES) <= tests.keys(), set(NAMES)-tests.keys()
	outputs = sorted({str(Path(path).relative_to(build)) for name in NAMES for dependency in tests[name]['depends']
		for path in targets[dependency]['filename']})
	compile_command = ['ninja', '-C', str(build), '-j', '4', *outputs]
	test_command = ['meson', 'test', '-C', str(build), '--no-rebuild', '--num-processes', '2',
		'--print-errorlogs', '--logbase', 'language-runtime-regressions', *NAMES]
	(build/'meson-logs/language-runtime-selection.json').write_text(json.dumps(
		dict(tests=NAMES, build_command=compile_command, test_command=test_command), indent=2)+'\n')
	environment = dict(os.environ, CCACHE_DISABLE='1', PYTHONDONTWRITEBYTECODE='1')
	subprocess.run(compile_command, env=environment, check=True)
	subprocess.run(test_command, env=environment, check=True)


if __name__ == '__main__': main(*sys.argv[1:])
