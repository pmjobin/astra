# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

loop_tests = executable('astra-loop-tests', 'pipeline.vala', dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('loops', loop_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())

loop_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['count', 'accumulate', 'body-local', 'bool-carried', 'call-loop', 'nested-loop', 'return-loop', 'post-return', 'body-return-tail', 'constant', 'trap-loop', 'condition-order', 'runtime-count']
	foreach mode : ['--parse', '--check']
		test('loop-' + mode.substring(2) + '-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', '-', '0'], workdir: loop_fixture_directory)
	endforeach
endforeach

foreach fixture : ['count', 'accumulate', 'body-local', 'call-loop', 'nested-loop', 'return-loop', 'bool-carried', 'trap-loop', 'body-return-tail', 'post-return', 'constant', 'condition-order']
	stages = ['ssa', 'llvm']
	if fixture == 'count'
		stages = ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'llvm']
	elif ['accumulate', 'body-local', 'call-loop', 'nested-loop', 'return-loop'].contains(fixture)
		stages = ['cfg', 'ssa', 'llvm']
	endif
	foreach stage : stages
		test('loop-' + stage + '-' + fixture, cli_check, args: [astrac, '--dump-' + stage, fixture + '.astra', fixture + (stage == 'llvm' ? '.ll' : '.' + stage), '-', '0'], workdir: loop_fixture_directory)
	endforeach
endforeach

foreach fixture : ['missing-condition', 'missing-parentheses', 'missing-close', 'missing-braces', 'malformed-body']
	foreach mode : ['--parse', '--dump-syntax', '--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']
		test('loop-' + mode.substring(2) + '-error-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: loop_fixture_directory)
	endforeach
endforeach
foreach fixture : ['int-condition', 'escape', 'shadow-local', 'shadow-parameter', 'self-initializer']
	foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']
		test('loop-' + mode.substring(2) + '-error-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: loop_fixture_directory)
	endforeach
endforeach
foreach fixture : ['partial', 'constant-partial']
	foreach mode : ['--check', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']
		test('loop-' + mode.substring(2) + '-error-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: loop_fixture_directory)
	endforeach
endforeach
