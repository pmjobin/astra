# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

release_tests = executable('astra-release-tests', ['support.vala', 'pipeline.vala', 'diagnostics.vala', 'lifetime.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('releases', release_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
release_llvm_tests = executable('astra-release-llvm-tests', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('releases-llvm', release_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
release_fixture_directory = meson.current_source_dir() / 'fixtures'
release_vapi_args = ['--vapi', own_fixture_directory / 'owned-resource.vapi', '--vapi', move_fixture_directory / 'move-resource.vapi', '--vapi', meson.project_source_root() / 'tests/oborrow/fixtures/borrowed-resource.vapi']
foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['basic', 'null', 'move', 'borrow', 'loop', 'move-loop', 'break', 'continue', 'order', 'lifo', 'others', 'multiple', 'contracts', 'shortcircuit', 'branch', 'memory', 'unreachable', 'conditional', 'both-arms', 'terminating-arm', 'loop-break', 'loop-return', 'null-conditional', 'return', 'three-way', 'trap']
		test('release' + mode + '-' + fixture, astrac, args: [mode, release_fixture_directory / 'release-' + fixture + '.astra'] + (mode == '--parse' or mode == '--dump-syntax' ? [] : release_vapi_args))
	endforeach
endforeach
foreach mode : ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	test('release-invalid' + mode, cli_check, args: [astrac, mode, 'release-invalid.astra', '-', 'release-invalid.stderr', '1', '--vapi', own_fixture_directory / 'owned-resource.vapi'], workdir: release_fixture_directory)
endforeach
foreach mode : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
	test('release-contract-golden-' + mode, cli_check, args: [astrac, '--dump-' + mode, 'release-contract.astra', 'release-contract.' + (mode == 'llvm' ? 'll' : mode), '-', '0'] + (mode == 'syntax' ? [] : ['--vapi', own_fixture_directory / 'owned-resource.vapi']), workdir: release_fixture_directory)
endforeach
foreach fixture : ['conditional', 'both-arms', 'three-way', 'move', 'loop', 'unreachable']
	test('release-' + fixture + '-golden-ssa', cli_check, args: [astrac, '--dump-ssa', 'release-' + fixture + '.astra', 'release-' + fixture + '.ssa', '-', '0'] + release_vapi_args, workdir: release_fixture_directory)
endforeach
