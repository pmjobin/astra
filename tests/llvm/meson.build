# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

llvm_tests = executable('astra-llvm-tests', ['pipeline.vala', 'control.vala', 'division.vala', 'lifetime.vala', 'loops.vala', 'loop-control.vala', 'shortcircuit.vala', 'c-imports.vala', 'c-exports.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('llvm-backend', llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())

# Retained LLVM 22 printer goldens describe this backend realization, not a symbol ABI.
llvm_fixture_directory = meson.current_source_dir() / 'fixtures'
llvm_fixtures = {
	'constants': llvm_fixture_directory / 'constants.astra',
	'wrapping': llvm_fixture_directory / 'wrapping.astra',
	'comparisons': llvm_fixture_directory / 'comparisons.astra',
	'choose': branch_fixture_directory / 'choose.astra',
	'multiple-merge': ssa_fixture_directory / 'multiple.astra',
	'choose-call': call_fixture_directory / 'choose-call.astra',
	'ordered-calls': call_fixture_directory / 'ordered-calls.astra',
	'nested-calls': call_fixture_directory / 'nested-calls.astra',
	'forward-call': call_fixture_directory / 'forward-call.astra',
	'recursion': call_fixture_directory / 'recursion.astra',
	'mutual-recursion': call_fixture_directory / 'mutual-recursion.astra',
	'division': scalar_fixture_directory / 'division.astra',
	'division-order': llvm_fixture_directory / 'division-order.astra',
	'division-phi': llvm_fixture_directory / 'division-phi.astra',
	'bool-phi': llvm_fixture_directory / 'bool-phi.astra',
}
foreach name, source : llvm_fixtures
	test('llvm-' + name, cli_check, args: [astrac, '--dump-llvm', source, llvm_fixture_directory / name + '.ll', '-', '0'])
	test('llvm-check-' + name, cli_check, args: [astrac, '--check', source, '-', '-', '0'])
endforeach
foreach fixture : ['missing-semicolon', 'unexpected-character', 'unterminated-comment', 'invalid-utf8', 'embedded-nul']
	test('llvm-parse-error-' + fixture, cli_check, args: [astrac, '--dump-llvm', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: fixture_directory)
endforeach
foreach fixture : ['unknown-return-type', 'unknown-parameter-type', 'void-parameter', 'duplicate-parameter', 'duplicate-function', 'duplicate-signature', 'unknown-name', 'int-bare-return', 'void-value-return']
	test('llvm-semantic-error-' + fixture, cli_check, args: [astrac, '--dump-llvm', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: semantic_fixture_directory)
endforeach
foreach fixture : ['unknown-function', 'too-few', 'too-many', 'argument-type', 'void-value']
	test('llvm-call-error-' + fixture, cli_check, args: [astrac, '--dump-llvm', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: call_fixture_directory)
endforeach
foreach fixture : ['too-large', 'too-small', 'positive-overflow', 'parenthesized-overflow', 'call-overflow', 'local-overflow', 'negative-local-overflow']
	test('llvm-scalar-error-' + fixture, cli_check, args: [astrac, '--dump-llvm', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: scalar_fixture_directory)
endforeach
foreach fixture : ['partial', 'constant-partial']
	test('llvm-flow-error-' + fixture, cli_check, args: [astrac, '--dump-llvm', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: branch_fixture_directory)
endforeach
test('llvm-late-flow-error', cli_check, args: [astrac, '--dump-llvm', 'programs.astra', '-', 'programs.flow-stderr', '1'], workdir: semantic_fixture_directory)
test('llvm-empty-int', cli_check, args: [astrac, '--dump-llvm', 'empty-int.astra', '-', 'empty-int.stderr', '1'], workdir: cfg_fixture_directory)
test('llvm-missing-file', cli_check, args: [astrac, '--dump-llvm', 'nonexistent.astra', '-', 'missing-file.stderr', '1'], workdir: fixture_directory)
test('llvm-missing-argument', astrac, args: ['--dump-llvm'], expected_exitcode: 2)
test('llvm-duplicate-source', astrac, args: ['--dump-llvm', 'first.astra', './first.astra'], expected_exitcode: 2)

llvm_branch_api = executable('astra-llvm-branch-api', 'branch-api.c', dependencies: llvm_dependency)
test('llvm-branch-api', llvm_branch_api)
