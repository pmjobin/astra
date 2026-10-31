# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

place_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['mutate', 'post-return', 'repeated', 'declaration-order', 'void-locals']
	foreach mode : ['--parse', '--check']
		test('place-' + mode.substring(2) + '-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', '-', '0'], workdir: place_fixture_directory)
	endforeach
endforeach
foreach fixture : ['mutate', 'post-return']
	foreach stage : ['semantics', 'core', 'cfg']
		test('place-' + stage + '-' + fixture, cli_check, args: [astrac, '--dump-' + stage, fixture + '.astra', fixture + '.' + stage, '-', '0'], workdir: place_fixture_directory)
	endforeach
endforeach
foreach fixture : ['mutate']
	test('place-syntax-' + fixture, cli_check, args: [astrac, '--dump-syntax', fixture + '.astra', fixture + '.syntax', '-', '0'], workdir: place_fixture_directory)
endforeach
foreach fixture : ['unknown-type', 'void-local', 'before-declaration', 'self-reference', 'duplicate', 'parameter-conflict', 'assignment-before', 'parameter-assignment']
	foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg']
		test('place-' + mode.substring(2) + '-error-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: place_fixture_directory)
	endforeach
endforeach
foreach fixture : ['missing-initializer', 'missing-rhs', 'missing-local-semicolon', 'missing-store-semicolon', 'assignment-expression', 'chaining']
	foreach mode : ['--parse', '--dump-syntax', '--check', '--dump-semantics', '--dump-core', '--dump-cfg']
		test('place-' + mode.substring(2) + '-error-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: place_fixture_directory)
	endforeach
endforeach
foreach mode : ['--check', '--dump-cfg']
	test('place-' + mode.substring(2) + '-flow-error', cli_check, args: [astrac, mode, 'local-end.astra', '-', 'local-end.stderr', '1'], workdir: place_fixture_directory)
endforeach
test('place-source-entry-required', astrac, args: files('fixtures/mutate.astra'), expected_exitcode: 1)
