# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

test('cli-help', astrac, args: ['--help'])
test('cli-version', astrac, args: ['--version'])
test('cli-no-action', astrac, expected_exitcode: 2)
test('cli-missing-source', astrac, args: ['example.astra'], expected_exitcode: 1)
test('cli-unknown-option', astrac, args: ['--unknown'], expected_exitcode: 2)
test('cli-help-with-source', astrac, args: ['--help', 'example.astra'], expected_exitcode: 2)
test('cli-end-of-options', astrac, args: ['--', '-example.astra'], expected_exitcode: 1)

llvm_smoke = executable('astra-llvm-smoke', ['llvm.vala', llvm_smoke_sources], dependencies: host_dependencies + [llvm_dependency], c_args: ['-DVALA_STRICT_C'])
test('llvm-module-valid', llvm_smoke)
test('llvm-verifier-rejects-invalid', llvm_smoke, args: ['--invalid'])
