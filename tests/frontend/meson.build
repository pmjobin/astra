# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

frontend_tests = executable('astra-frontend-tests', ['tests.vala', 'locals.vala', 'branches.vala', 'calls.vala'], dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('frontend', frontend_tests, args: ['--tap'], protocol: 'tap')

cli_check = executable('astra-cli-check', 'cli-check.vala', dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['empty', 'functions', 'precedence']
	test('parse-' + fixture, cli_check, args: [astrac, '--parse', fixture + '.astra', '-', '-', '0'], workdir: fixture_directory)
	test('dump-' + fixture, cli_check, args: [astrac, '--dump-syntax', fixture + '.astra', fixture + '.syntax', '-', '0'], workdir: fixture_directory)
endforeach
foreach fixture : ['missing-semicolon', 'unexpected-character', 'unterminated-comment', 'invalid-utf8', 'embedded-nul']
	test('parse-error-' + fixture, cli_check, args: [astrac, '--parse', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: fixture_directory)
	test('dump-error-' + fixture, cli_check, args: [astrac, '--dump-syntax', fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: fixture_directory)
endforeach
test('parse-missing-file', cli_check, args: [astrac, '--parse', 'nonexistent.astra', '-', 'missing-file.stderr', '1'], workdir: fixture_directory)
test('parse-missing-argument', astrac, args: ['--parse'], expected_exitcode: 2)
test('dump-missing-argument', astrac, args: ['--dump-syntax'], expected_exitcode: 2)
test('parse-multiple-missing-inputs', astrac, args: ['--parse', 'first.astra', 'second.astra'], expected_exitcode: 1)
