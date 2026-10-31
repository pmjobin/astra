# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

loopctrl_tests = executable('astra-loopctrl-tests', 'pipeline.vala', dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('loop-control', loopctrl_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())

loopctrl_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['break-basic', 'continue-basic', 'break-merge', 'continue-merge', 'nested-loop-control', 'multiple-sites', 'edge-state', 'unreachable', 'trap-control']
	foreach mode : ['--parse', '--check', '--dump-nabi']
		test('loopctrl-' + mode.substring(2) + '-' + fixture, astrac, args: [mode, loopctrl_fixture_directory / fixture + '.astra'])
	endforeach
endforeach

foreach fixture : ['break-basic', 'continue-basic', 'break-merge', 'continue-merge', 'nested-loop-control', 'multiple-sites', 'trap-control']
	stages = ['cfg', 'ssa', 'llvm']
	if ['break-basic', 'continue-basic', 'break-merge', 'continue-merge', 'nested-loop-control'].contains(fixture)
		stages = ['syntax', 'semantics', 'core'] + stages
	endif
	foreach stage : stages
		test('loopctrl-' + stage + '-' + fixture, cli_check, args: [astrac, '--dump-' + stage, fixture + '.astra', fixture + (stage == 'llvm' ? '.ll' : '.' + stage), '-', '0'], workdir: loopctrl_fixture_directory)
	endforeach
endforeach
foreach fixture : ['missing-break-semicolon', 'missing-continue-semicolon']
	foreach mode : ['--parse', '--dump-syntax', '--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']
		test('loopctrl-' + mode.substring(2) + '-error-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: loopctrl_fixture_directory)
	endforeach
endforeach
foreach fixture : ['outside-break', 'outside-continue']
	test('loopctrl-parse-' + fixture, astrac, args: ['--parse', loopctrl_fixture_directory / fixture + '.astra'])
	foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']
		test('loopctrl-' + mode.substring(2) + '-error-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: loopctrl_fixture_directory)
	endforeach
	test('loopctrl-native-error-' + fixture, astrac, args: [loopctrl_fixture_directory / fixture + '.astra'], expected_exitcode: 1)
endforeach
foreach mode : ['--check', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']
	test('loopctrl-' + mode.substring(2) + '-error-partial', cli_check, args: [astrac, mode, 'partial.astra', '-', 'partial.stderr', '1'], workdir: loopctrl_fixture_directory)
endforeach
foreach mode : ['--parse', '--dump-semantics', '--dump-core']
	test('loopctrl-' + mode.substring(2) + '-partial', astrac, args: [mode, loopctrl_fixture_directory / 'partial.astra'])
endforeach
