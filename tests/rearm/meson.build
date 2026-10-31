# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

rearm_tests = executable('astra-rearm-tests', ['support.vala', 'pipeline.vala', 'diagnostics.vala', 'lifetime.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('rearms', rearm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
rearm_llvm_tests = executable('astra-rearm-llvm-tests', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('rearms-llvm', rearm_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
rearm_fixture_directory = meson.current_source_dir() / 'fixtures'
rearm_vapi_args = ['--vapi', own_fixture_directory / 'owned-resource.vapi', '--vapi', rearm_fixture_directory / 'rearm-resource.vapi', '--vapi', meson.project_source_root() / 'tests/oborrow/fixtures/borrowed-resource.vapi']
foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['release', 'move', 'mixed', 'conditional', 'both-arms', 'both-moved', 'both-released', 'null', 'null-release', 'multiple', 'move-cycles', 'borrow', 'order', 'branch-order', 'effects', 'terminating', 'terminating-disarmed', 'unreachable', 'loop', 'continue', 'move-loop', 'move-continue', 'mixed-loop', 'break', 'trap']
		test('rearm' + mode + '-' + fixture, astrac, args: [mode, rearm_fixture_directory / 'rearm-' + fixture + '.astra'] + (mode == '--parse' or mode == '--dump-syntax' ? [] : rearm_vapi_args))
	endforeach
endforeach
foreach mode : ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	test('rearm-invalid' + mode, cli_check, args: [astrac, mode, 'rearm-invalid.astra', '-', 'rearm-invalid.stderr', '1', '--vapi', own_fixture_directory / 'owned-resource.vapi'], workdir: rearm_fixture_directory)
endforeach
foreach mode : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
	test('rearm-contract-golden-' + mode, cli_check, args: [astrac, '--dump-' + mode, 'rearm-contract.astra', 'rearm-contract.' + (mode == 'llvm' ? 'll' : mode), '-', '0'] + (mode == 'syntax' ? [] : ['--vapi', own_fixture_directory / 'owned-resource.vapi']), workdir: rearm_fixture_directory)
endforeach
foreach fixture : ['conditional', 'both-arms', 'mixed', 'move', 'loop', 'move-loop', 'order']
	test('rearm-' + fixture + '-golden-ssa', cli_check, args: [astrac, '--dump-ssa', 'rearm-' + fixture + '.astra', 'rearm-' + fixture + '.ssa', '-', '0'] + rearm_vapi_args, workdir: rearm_fixture_directory)
endforeach
