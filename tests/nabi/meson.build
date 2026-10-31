# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

nabi_tests = executable('astra-nabi-tests', ['pipeline.vala', 'lifetime.vala', 'call-validation.vala'], dependencies: nabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('nabi', nabi_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())

# Physical representation only: no semantic types/operators, syntax, checked
# model, Core, CFG, SSA, planners, or backend sources.
nabi_standalone_tests = executable('astra-nabi-standalone-tests', ['standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('nabi-standalone', nabi_standalone_tests, args: ['--tap'], protocol: 'tap')

nabi_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['signatures', 'zero-arguments', 'mixed', 'bool-transport']
	test('nabi-' + fixture, cli_check, args: [astrac, '--dump-nabi', fixture + '.astra', fixture + '.nabi', '-', '0'], workdir: nabi_fixture_directory)
	test('nabi-check-' + fixture, cli_check, args: [astrac, '--check', fixture + '.astra', '-', '-', '0'], workdir: nabi_fixture_directory)
endforeach
foreach fixture : ['forward-call', 'recursion', 'mutual-recursion', 'bool-calls', 'statements', 'ordered-calls', 'nested-calls', 'choose-call', 'places-calls', 'branch-calls', 'unreachable-call', 'namespace']
	test('nabi-call-' + fixture, cli_check, args: [astrac, '--dump-nabi', fixture + '.astra', nabi_fixture_directory / fixture + '.nabi', '-', '0'], workdir: call_fixture_directory)
endforeach
foreach fixture : ['boundaries', 'leading', 'wrapping', 'division', 'calls', 'trap-order']
	test('nabi-scalar-' + fixture, cli_check, args: [astrac, '--dump-nabi', fixture + '.astra', nabi_fixture_directory / 'scalar-' + fixture + '.nabi', '-', '0'], workdir: scalar_fixture_directory)
endforeach
test('nabi-empty', cli_check, args: [astrac, '--dump-nabi', 'empty.astra', nabi_fixture_directory / 'empty.nabi', '-', '0'], workdir: fixture_directory)

foreach fixture : ['missing-semicolon', 'unexpected-character', 'unterminated-comment', 'invalid-utf8', 'embedded-nul']
	test('nabi-parse-error-' + fixture, cli_check, args: [astrac, '--dump-nabi', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: fixture_directory)
endforeach
foreach fixture : ['unknown-return-type', 'unknown-parameter-type', 'void-parameter', 'duplicate-parameter', 'duplicate-function', 'duplicate-signature', 'unknown-name', 'int-bare-return', 'void-value-return']
	test('nabi-semantic-error-' + fixture, cli_check, args: [astrac, '--dump-nabi', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: semantic_fixture_directory)
endforeach
foreach fixture : ['unknown-function', 'too-few', 'too-many', 'argument-type', 'void-value']
	test('nabi-call-error-' + fixture, cli_check, args: [astrac, '--dump-nabi', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: call_fixture_directory)
endforeach
foreach fixture : ['too-large', 'too-small', 'positive-overflow', 'parenthesized-overflow', 'call-overflow', 'local-overflow', 'negative-local-overflow']
	test('nabi-scalar-error-' + fixture, cli_check, args: [astrac, '--dump-nabi', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: scalar_fixture_directory)
endforeach
foreach fixture : ['partial', 'constant-partial']
	test('nabi-flow-error-' + fixture, cli_check, args: [astrac, '--dump-nabi', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: branch_fixture_directory)
endforeach
test('nabi-late-flow-error', cli_check, args: [astrac, '--dump-nabi', 'programs.astra', '-', 'programs.flow-stderr', '1'], workdir: semantic_fixture_directory)
test('nabi-empty-int', cli_check, args: [astrac, '--dump-nabi', 'empty-int.astra', '-', 'empty-int.stderr', '1'], workdir: cfg_fixture_directory)
test('nabi-missing-file', cli_check, args: [astrac, '--dump-nabi', 'nonexistent.astra', '-', 'missing-file.stderr', '1'], workdir: fixture_directory)
test('nabi-missing-argument', astrac, args: ['--dump-nabi'], expected_exitcode: 2)
test('nabi-duplicate-source', astrac, args: ['--dump-nabi', 'first.astra', './first.astra'], expected_exitcode: 2)
