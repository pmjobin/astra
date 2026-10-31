# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

call_fixture_directory = meson.current_source_dir() / 'fixtures'
call_tests = executable('astra-call-tests', 'tests.vala', dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('calls', call_tests, args: ['--tap'], protocol: 'tap', workdir: call_fixture_directory)

foreach fixture : ['forward-call', 'recursion', 'mutual-recursion', 'ordered-calls', 'nested-calls', 'choose-call', 'statements', 'bool-calls', 'places-calls', 'branch-calls', 'unreachable-call', 'namespace']
	test('call-parse-' + fixture, cli_check, args: [astrac, '--parse', fixture + '.astra', '-', '-', '0'], workdir: call_fixture_directory)
	test('call-check-' + fixture, cli_check, args: [astrac, '--check', fixture + '.astra', '-', '-', '0'], workdir: call_fixture_directory)
	foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa']
		test('call-' + stage + '-' + fixture, cli_check, args: [astrac, '--dump-' + stage, fixture + '.astra', fixture + '.' + stage, '-', '0'], workdir: call_fixture_directory)
	endforeach
endforeach
foreach fixture : ['unknown-function', 'too-few', 'too-many', 'argument-type', 'void-value']
	foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa']
		test('call-error-' + mode.substring(2) + '-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: call_fixture_directory)
	endforeach
endforeach
test('call-source-entry-required', astrac, args: files('fixtures/forward-call.astra'), expected_exitcode: 1)
