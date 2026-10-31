# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

branch_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['choose', 'choose-direct', 'nested', 'siblings', 'boolean-place', 'operators', 'post-return', 'no-else', 'constant']
	foreach mode : ['--parse', '--check']
		test('branch-' + mode.substring(2) + '-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', '-', '0'], workdir: branch_fixture_directory)
	endforeach
	foreach stage : ['syntax', 'semantics', 'core', 'cfg']
		test('branch-' + stage + '-' + fixture, cli_check, args: [astrac, '--dump-' + stage, fixture + '.astra', fixture + '.' + stage, '-', '0'], workdir: branch_fixture_directory)
	endforeach
endforeach
foreach fixture : ['partial', 'constant-partial']
	foreach stage : ['syntax', 'semantics', 'core']
		test('branch-' + stage + '-' + fixture, cli_check, args: [astrac, '--dump-' + stage, fixture + '.astra', fixture + '.' + stage, '-', '0'], workdir: branch_fixture_directory)
	endforeach
	foreach mode : ['--check', '--dump-cfg']
		test('branch-' + mode.substring(2) + '-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: branch_fixture_directory)
	endforeach
endforeach
foreach fixture : ['escape', 'sibling-visibility', 'shadow-outer', 'shadow-parameter', 'int-condition', 'unequal-types', 'not-int']
	foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg']
		test('branch-' + mode.substring(2) + '-error-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: branch_fixture_directory)
	endforeach
endforeach
foreach fixture : ['missing-parentheses', 'missing-braces', 'else-if']
	foreach mode : ['--parse', '--dump-syntax', '--check', '--dump-semantics', '--dump-core', '--dump-cfg']
		test('branch-' + mode.substring(2) + '-error-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: branch_fixture_directory)
	endforeach
endforeach
test('branch-source-entry-required', astrac, args: files('fixtures/choose.astra'), expected_exitcode: 1)
