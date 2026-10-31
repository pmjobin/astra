# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# Core construction tests include the checked frontend, with no backend inputs.
core_tests = executable('astra-core-tests', ['tests.vala', 'places.vala', 'branches.vala', 'branch-operators.vala'], dependencies: core_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('core', core_tests, args: ['--tap'], protocol: 'tap')

# Compile the completed representation without syntax, checked nodes/symbols,
# builders, or backend inputs, including the local storage kinds.
core_standalone_tests = executable('astra-core-standalone-tests', ['standalone.vala', 'standalone-branches.vala', 'standalone-structs.vala', 'standalone-tptr.vala', 'standalone-calls.vala', 'standalone-owned.vala', 'standalone-loops.vala', 'standalone-shortcircuit.vala', 'standalone-loop-control.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('core-standalone', core_standalone_tests, args: ['--tap'], protocol: 'tap')

core_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['arithmetic', 'structure']
	test('core-' + fixture, cli_check, args: [astrac, '--dump-core', fixture + '.astra', fixture + '.core', '-', '0'], workdir: core_fixture_directory)
endforeach
test('core-empty', cli_check, args: [astrac, '--dump-core', 'empty.astra', core_fixture_directory / 'empty.core', '-', '0'], workdir: fixture_directory)

# Existing diagnostics must survive the complete Core path, with empty stdout.
foreach fixture : ['missing-semicolon', 'unexpected-character', 'unterminated-comment', 'invalid-utf8', 'embedded-nul']
	test('core-parse-error-' + fixture, cli_check, args: [astrac, '--dump-core', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: fixture_directory)
endforeach
foreach fixture : ['unknown-return-type', 'unknown-parameter-type', 'void-parameter', 'duplicate-parameter', 'duplicate-function', 'duplicate-signature', 'unknown-name', 'int-bare-return', 'void-value-return']
	test('core-semantic-error-' + fixture, cli_check, args: [astrac, '--dump-core', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: semantic_fixture_directory)
endforeach
test('core-missing-file', cli_check, args: [astrac, '--dump-core', 'nonexistent.astra', '-', 'missing-file.stderr', '1'], workdir: fixture_directory)
test('core-missing-argument', astrac, args: ['--dump-core'], expected_exitcode: 2)
test('core-duplicate-source', astrac, args: ['--dump-core', 'first.astra', './first.astra'], expected_exitcode: 2)
test('core-source-entry-required', astrac, args: files('fixtures/arithmetic.astra'), expected_exitcode: 1)
