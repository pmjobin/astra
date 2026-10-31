# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

cfg_tests = executable('astra-cfg-tests', ['tests.vala', 'places.vala', 'branches.vala', 'branch-operators.vala'], dependencies: cfg_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('cfg', cfg_tests, args: ['--tap'], protocol: 'tap')

# A compiled structural firewall: no syntax, checked model, symbols, Core
# nodes/builder, CFG builder, or backend inputs are available to this target.
cfg_standalone_tests = executable('astra-cfg-standalone-tests', ['standalone.vala', 'standalone-branches.vala', 'standalone-structs.vala', 'standalone-tptr.vala', 'standalone-calls.vala', 'standalone-owned.vala', 'standalone-evaluation.vala', 'standalone-loops.vala', 'standalone-shortcircuit.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('cfg-standalone', cfg_standalone_tests, args: ['--tap'], protocol: 'tap')

cfg_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['arithmetic', 'sequential', 'empty-void']
	test('cfg-' + fixture, cli_check, args: [astrac, '--dump-cfg', fixture + '.astra', fixture + '.cfg', '-', '0'], workdir: cfg_fixture_directory)
	test('cfg-check-' + fixture, cli_check, args: [astrac, '--check', fixture + '.astra', '-', '-', '0'], workdir: cfg_fixture_directory)
endforeach
test('cfg-empty', cli_check, args: [astrac, '--dump-cfg', 'empty.astra', cfg_fixture_directory / 'empty.cfg', '-', '0'], workdir: fixture_directory)

foreach mode : ['--check', '--dump-cfg']
	test('cfg-empty-int-' + mode.substring(2), cli_check, args: [astrac, mode, 'empty-int.astra', '-', 'empty-int.stderr', '1'], workdir: cfg_fixture_directory)
endforeach
test('cfg-empty-int-parse', cli_check, args: [astrac, '--parse', 'empty-int.astra', '-', '-', '0'], workdir: cfg_fixture_directory)
test('cfg-empty-int-semantics', cli_check, args: [astrac, '--dump-semantics', 'empty-int.astra', 'empty-int.semantics', '-', '0'], workdir: cfg_fixture_directory)
test('cfg-empty-int-core', cli_check, args: [astrac, '--dump-core', 'empty-int.astra', 'empty-int.core', '-', '0'], workdir: cfg_fixture_directory)
# Earlier valid functions must not escape as a partial dump on a later error.
test('cfg-late-flow-error', cli_check, args: [astrac, '--dump-cfg', 'programs.astra', '-', 'programs.flow-stderr', '1'], workdir: semantic_fixture_directory)

foreach fixture : ['missing-semicolon', 'unexpected-character', 'unterminated-comment', 'invalid-utf8', 'embedded-nul']
	test('cfg-parse-error-' + fixture, cli_check, args: [astrac, '--dump-cfg', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: fixture_directory)
endforeach
foreach fixture : ['unknown-return-type', 'unknown-parameter-type', 'void-parameter', 'duplicate-parameter', 'duplicate-function', 'duplicate-signature', 'unknown-name', 'int-bare-return', 'void-value-return']
	test('cfg-semantic-error-' + fixture, cli_check, args: [astrac, '--dump-cfg', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: semantic_fixture_directory)
endforeach
test('cfg-missing-file', cli_check, args: [astrac, '--dump-cfg', 'nonexistent.astra', '-', 'missing-file.stderr', '1'], workdir: fixture_directory)
test('cfg-missing-argument', astrac, args: ['--dump-cfg'], expected_exitcode: 2)
test('cfg-duplicate-source', astrac, args: ['--dump-cfg', 'first.astra', './first.astra'], expected_exitcode: 2)
test('cfg-source-entry-required', astrac, args: files('fixtures/arithmetic.astra'), expected_exitcode: 1)
