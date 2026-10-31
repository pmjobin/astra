# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

own_tests = executable('astra-own-tests', ['support.vala', 'pipeline.vala', 'diagnostics.vala', 'lifetime.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ownership', own_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
own_llvm_tests = executable('astra-own-llvm-tests', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ownership-llvm', own_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
own_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['basic', 'null', 'lifo', 'nested', 'return', 'early-return', 'branch', 'branch-both', 'loop', 'continue', 'break', 'loop-return', 'shortcircuit', 'mixed', 'unreachable', 'nested-loop', 'fallthrough', 'trap', 'null-trap']
		test('own' + mode + '-' + fixture, astrac, args: [mode, own_fixture_directory / 'own-' + fixture + '.astra'] + (mode == '--parse' or mode == '--dump-syntax' ? [] : ['--vapi', own_fixture_directory / 'owned-resource.vapi']))
	endforeach
endforeach
foreach mode : ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	test('own-invalid' + mode, cli_check, args: [astrac, mode, 'own-invalid.astra', '-', 'own-invalid.stderr', '1', '--vapi', 'owned-resource.vapi'], workdir: own_fixture_directory)
	test('owned-invalid-vapi' + mode, cli_check, args: [astrac, mode, 'own-basic.astra', '-', 'owned-invalid.stderr', '1', '--vapi', 'owned-invalid.vapi'], workdir: own_fixture_directory)
endforeach
foreach mode : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'cabi', 'llvm']
	test('own-basic-golden-' + mode, cli_check, args: [astrac, '--dump-' + mode, 'own-basic.astra', 'own-basic.' + (mode == 'llvm' ? 'll' : mode), '-', '0'] + (mode == 'syntax' ? [] : ['--vapi', 'owned-resource.vapi']), workdir: own_fixture_directory)
endforeach
foreach fixture : ['lifo', 'return', 'continue', 'branch', 'unreachable']
	test('own-' + fixture + '-golden-ssa', cli_check, args: [astrac, '--dump-ssa', 'own-' + fixture + '.astra', 'own-' + fixture + '.ssa', '-', '0', '--vapi', 'owned-resource.vapi'], workdir: own_fixture_directory)
endforeach
