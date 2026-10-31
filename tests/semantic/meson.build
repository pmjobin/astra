# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# No backend sources, bindings, or link dependencies enter this target.
semantic_tests = executable('astra-semantic-tests', ['tests.vala', 'locals.vala', 'branches.vala', 'calls.vala'], dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('semantic', semantic_tests, args: ['--tap'], protocol: 'tap')

semantic_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['programs', 'operators', 'namespaces']
	if fixture == 'programs'
		# Semantic validity still permits this fixture's empty int body;
		# the full --check pipeline now diagnoses its reachable function end.
		test('check-' + fixture, cli_check, args: [astrac, '--check', fixture + '.astra', '-', fixture + '.flow-stderr', '1'], workdir: semantic_fixture_directory)
	else
		test('check-' + fixture, cli_check, args: [astrac, '--check', fixture + '.astra', '-', '-', '0'], workdir: semantic_fixture_directory)
	endif
	test('semantics-' + fixture, cli_check, args: [astrac, '--dump-semantics', fixture + '.astra', fixture + '.semantics', '-', '0'], workdir: semantic_fixture_directory)
endforeach
foreach fixture : ['unknown-return-type', 'unknown-parameter-type', 'void-parameter', 'duplicate-parameter', 'duplicate-function', 'duplicate-signature', 'unknown-name', 'int-bare-return', 'void-value-return']
	test('check-error-' + fixture, cli_check, args: [astrac, '--check', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: semantic_fixture_directory)
	test('semantics-error-' + fixture, cli_check, args: [astrac, '--dump-semantics', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: semantic_fixture_directory)
endforeach

# Reuse the accepted encoding/lexer/parser fixtures without changing goldens.
foreach mode : ['--check', '--dump-semantics']
	foreach fixture : ['missing-semicolon', 'unexpected-character', 'unterminated-comment', 'invalid-utf8', 'embedded-nul']
		test(mode.substring(2) + '-parse-error-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: fixture_directory)
	endforeach
	test(mode.substring(2) + '-missing-file', cli_check, args: [astrac, mode, 'nonexistent.astra', '-', 'missing-file.stderr', '1'], workdir: fixture_directory)
	test(mode.substring(2) + '-missing-argument', astrac, args: [mode], expected_exitcode: 2)
	test(mode.substring(2) + '-duplicate-source', astrac, args: [mode, 'first.astra', './first.astra'], expected_exitcode: 2)
endforeach
test('check-empty', cli_check, args: [astrac, '--check', 'empty.astra', '-', '-', '0'], workdir: fixture_directory)
test('semantics-empty', cli_check, args: [astrac, '--dump-semantics', 'empty.astra', semantic_fixture_directory / 'empty.semantics', '-', '0'], workdir: fixture_directory)
test('parse-semantic-error-is-valid-syntax', cli_check, args: [astrac, '--parse', 'unknown-return-type.astra', '-', '-', '0'], workdir: semantic_fixture_directory)
test('semantic-source-flow-error', astrac, args: files('fixtures/programs.astra'), expected_exitcode: 1)
