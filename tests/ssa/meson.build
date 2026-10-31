# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

dominance_tests = executable('astra-dominance-tests', ['dominance-tests.vala', 'cfg-test-support.vala', ssa_analysis_sources], dependencies: cfg_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dominance', dominance_tests, args: ['--tap'], protocol: 'tap')

ssa_tests = executable('astra-ssa-tests', ['ssa-tests.vala', 'ssa-lifetime.vala', 'cfg-test-support.vala'], dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ssa', ssa_tests, args: ['--tap'], protocol: 'tap')

# No syntax, symbols, checked model, Core, CFG, builder, or backend inputs.
ssa_standalone_tests = executable('astra-ssa-standalone-tests', ['ssa-standalone.vala', 'standalone-calls.vala', 'standalone-owned.vala', 'standalone-loops.vala', 'standalone-shortcircuit.vala', 'standalone-field-origins.vala', 'standalone-memory.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ssa-standalone', ssa_standalone_tests, args: ['--tap'], protocol: 'tap')

ssa_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['straight', 'maybe', 'multiple', 'arithmetic', 'comparison', 'scoped', 'dead-merge']
	test('ssa-' + fixture, cli_check, args: [astrac, '--dump-ssa', fixture + '.astra', fixture + '.ssa', '-', '0'], workdir: ssa_fixture_directory)
	test('ssa-check-' + fixture, cli_check, args: [astrac, '--check', fixture + '.astra', '-', '-', '0'], workdir: ssa_fixture_directory)
endforeach
foreach fixture : ['choose', 'choose-direct', 'nested', 'siblings', 'boolean-place', 'operators', 'post-return', 'no-else', 'constant']
	test('ssa-branch-' + fixture, cli_check, args: [astrac, '--dump-ssa', fixture + '.astra', ssa_fixture_directory / fixture + '.ssa', '-', '0'], workdir: branch_fixture_directory)
endforeach
foreach fixture : ['mutate', 'repeated', 'post-return', 'void-locals']
	test('ssa-place-' + fixture, cli_check, args: [astrac, '--dump-ssa', fixture + '.astra', ssa_fixture_directory / 'place-' + fixture + '.ssa', '-', '0'], workdir: place_fixture_directory)
endforeach
test('ssa-empty', cli_check, args: [astrac, '--dump-ssa', 'empty.astra', ssa_fixture_directory / 'empty.ssa', '-', '0'], workdir: fixture_directory)
test('ssa-empty-void', cli_check, args: [astrac, '--dump-ssa', 'empty-void.astra', ssa_fixture_directory / 'empty-void.ssa', '-', '0'], workdir: cfg_fixture_directory)

foreach fixture : ['partial', 'constant-partial', 'escape', 'sibling-visibility', 'shadow-outer', 'shadow-parameter', 'int-condition', 'unequal-types', 'not-int', 'missing-parentheses', 'missing-braces', 'else-if']
	test('ssa-error-' + fixture, cli_check, args: [astrac, '--dump-ssa', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: branch_fixture_directory)
endforeach
foreach fixture : ['missing-semicolon', 'unexpected-character', 'unterminated-comment', 'invalid-utf8', 'embedded-nul']
	test('ssa-parse-error-' + fixture, cli_check, args: [astrac, '--dump-ssa', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: fixture_directory)
endforeach
foreach fixture : ['unknown-return-type', 'unknown-parameter-type', 'void-parameter', 'duplicate-parameter', 'duplicate-function', 'duplicate-signature', 'unknown-name', 'int-bare-return', 'void-value-return']
	test('ssa-semantic-error-' + fixture, cli_check, args: [astrac, '--dump-ssa', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: semantic_fixture_directory)
endforeach
test('ssa-late-flow-error', cli_check, args: [astrac, '--dump-ssa', 'programs.astra', '-', 'programs.flow-stderr', '1'], workdir: semantic_fixture_directory)
test('ssa-empty-int', cli_check, args: [astrac, '--dump-ssa', 'empty-int.astra', '-', 'empty-int.stderr', '1'], workdir: cfg_fixture_directory)
test('ssa-missing-file', cli_check, args: [astrac, '--dump-ssa', 'nonexistent.astra', '-', 'missing-file.stderr', '1'], workdir: fixture_directory)
test('ssa-missing-argument', astrac, args: ['--dump-ssa'], expected_exitcode: 2)
test('ssa-duplicate-source', astrac, args: ['--dump-ssa', 'first.astra', './first.astra'], expected_exitcode: 2)
