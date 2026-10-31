# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
"""Build and run a named cross-family Meson selection in the shared build."""
from pathlib import Path
import json
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
NAMES = '''
application-runtime-1-contracts application-runtime-1-execution
text-own-1a-contracts text-own-1a-native-execution
text-own-1b-contracts text-own-1b-native-execution text-own-1b-source-refusals
gen-member-1a-contracts gen-member-1a-native-execution gen-member-1a-source-refusals
container-1a-contracts container-1a-native-execution container-1a-source-refusals
app-diag-collection-0 gen-own-2d-contracts gen-own-2d-native-execution gen-own-2d-negative
gen-borrow-1-contracts gen-borrow-1-native-execution gen-borrow-1-negative
gen-buffer-pipeline gen-slice-pipeline obj-own-pipeline text-semantic
error-1-snapshot error-1-heap error-1-native-execution
obj-field-2-stage-contracts obj-field-2-native-execution
obj-alloc-1-loan-contracts obj-alloc-1-native-execution
struct-move-1-stage-contracts struct-move-1-native-execution
gen-own-2a-contracts gen-own-2a-native-execution gen-own-2a-negative gen-own-2a-no-llvm
gen-own-2b-contracts gen-own-2b-native-execution gen-own-2b-negative gen-own-2b-no-llvm
gen-own-2c-contracts gen-own-2c-native-execution gen-own-2c-negative gen-own-2c-no-llvm
gen-struct-parser gen-struct-semantic gen-struct-pipeline
gen-semantic gen-pipeline gen-cap-semantic gen-copy-semantic gen-copy-pipeline
own-swap-core own-swap-cfg own-swap-ssa own-swap-llvm
async-1-runtime-protocol async-1-native-frames async-1-source-frame-execution
ints-reference ints-reference-ubsan ints-semantic-standalone ints-core-standalone
ints-cfg-standalone ints-ssa-standalone ints-nabi-standalone ints-pipeline ints-llvm ints-native-execution
iconv-integer-value-standalone iconv-pipeline iconv-llvm
num-conv-semantic num-conv-core num-conv-cfg num-conv-ssa num-conv-pipeline num-conv-llvm
num-conv-native-oracle num-conv-suffix-oracle
f32-llvm f64-llvm f32-native-execution f64-native-execution
cabi-standalone cabi-fp-pipeline cabi-fp-llvm cabi-fp-native-execution
native-execution llvm-backend llvm-module-valid llvm-verifier-rejects-invalid
buffer-pipeline buffer-native-execution buffer-negative
sources-parser sources-semantic sources-pipeline sources-core sources-cfg sources-ssa sources-nabi sources-cabi
sources-llvm sources-llvm-standalone sources-composition-execution-permutations sources-negative-provenance
wide-values wide-values-ubsan wide-ssa-verifier wide-llvm-verifier wide-public-execution
cabi-buffer-standalone cabi-buffer-pipeline cabi-buffer-provider cabi-buffer-qualification
modules-1-scopes-execution compiler-systems-2-optimizer-contracts
compiler-systems-2-applications compiler-systems-2-predecessor-public-O2
'''.split()


def main(build, list_only=False):
	build = Path(build).resolve()
	assert not build.is_relative_to(ROOT)
	info = build/'meson-info'
	assert Path(json.loads((info/'meson-info.json').read_text())['directories']['source']).resolve() == ROOT
	if not list_only:
		subprocess.run(['meson','setup','--reconfigure',str(build),str(ROOT)],check=True)
	tests = {x['name']:x for x in json.loads((info/'intro-tests.json').read_text())}
	targets = {x['id']:x for x in json.loads((info/'intro-targets.json').read_text())}
	assert len(NAMES) == len(set(NAMES)) and set(NAMES) <= tests.keys(), set(NAMES)-tests.keys()
	outputs = sorted({str(Path(p).relative_to(build)) for name in NAMES for dependency in tests[name]['depends']
		for p in targets[dependency]['filename']})
	build_command = ['ninja','-C',str(build),'-j','4',*outputs]
	test_command = ['meson','test','-C',str(build),'--no-rebuild','--num-processes','2',
		'--print-errorlogs','--logbase','compiler-systems-regressions',*NAMES]
	plan = dict(source=str(ROOT),build=str(build),tests=NAMES,build_command=build_command,test_command=test_command)
	if list_only:
		print(json.dumps(dict(tests=len(NAMES),build_outputs=len(outputs)),indent=2)); return
	(build/'meson-logs/compiler-systems-selection.json').write_text(json.dumps(plan,indent=2)+'\n')
	environment=dict(os.environ,CCACHE_DISABLE='1',PYTHONDONTWRITEBYTECODE='1')
	subprocess.run(build_command,check=True,env=environment)
	subprocess.run(test_command,check=True,env=environment)


if __name__=='__main__': main(sys.argv[1],len(sys.argv)>2 and sys.argv[2]=='--list')
