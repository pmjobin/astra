# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

shortcircuit_tests = executable('astra-shortcircuit-tests', 'pipeline.vala', dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('short-circuit', shortcircuit_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())

shortcircuit_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['logical-and', 'logical-or', 'nested-short', 'call-short', 'loop-short', 'trap-short', 'contexts-short']
	foreach mode : ['--parse', '--check', '--dump-nabi']
		test('shortcircuit-' + mode.substring(2) + '-' + fixture, astrac, args: [mode, shortcircuit_fixture_directory / fixture + '.astra'])
	endforeach
	foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'llvm']
		test('shortcircuit-' + stage + '-' + fixture, cli_check, args: [astrac, '--dump-' + stage, fixture + '.astra', fixture + (stage == 'llvm' ? '.ll' : '.' + stage), '-', '0'], workdir: shortcircuit_fixture_directory)
	endforeach
endforeach
foreach fixture : ['rhs-missing-and', 'rhs-missing-or', 'rhs-overflow', 'operand-type']
	foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']
		test('shortcircuit-error-' + mode.substring(2) + '-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: shortcircuit_fixture_directory)
	endforeach
	test('shortcircuit-parse-' + fixture, astrac, args: ['--parse', shortcircuit_fixture_directory / fixture + '.astra'])
endforeach

# BIT-1 now accepts these eager boolean operators; the lazy goldens above
# still freeze the existing expression-level short-circuit CFG.
foreach fixture : ['single-and', 'single-or']
	foreach mode : ['--parse', '--dump-syntax', '--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm']
		test('shortcircuit-eager-' + mode.substring(2) + '-' + fixture, astrac, args: [mode, shortcircuit_fixture_directory / fixture + '.astra'])
	endforeach
endforeach
