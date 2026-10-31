# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

move_tests = executable('astra-move-tests', ['support.vala', 'pipeline.vala', 'diagnostics.vala', 'lifetime.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('moves', move_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
move_llvm_tests = executable('astra-move-llvm-tests', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('moves-llvm', move_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
# No syntax, checked symbols, Core, builder, SSA, ABI or LLVM sources.
ownership_flow_tests = executable('astra-ownership-flow-tests', ['standalone.vala', 'release-standalone.vala', 'rearm-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ownership-flow-standalone', ownership_flow_tests, args: ['--tap'], protocol: 'tap')
move_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['basic', 'chain', 'chain-lifo', 'null', 'conditional', 'both-arms', 'return', 'break', 'continue', 'loop', 'lifo', 'contracts', 'terminating-arm', 'loop-break', 'loop-return', 'conditional-break', 'mixed', 'unreachable', 'trap']
		test('move' + mode + '-' + fixture, astrac, args: [mode, move_fixture_directory / 'move-' + fixture + '.astra'] + (mode == '--parse' or mode == '--dump-syntax' ? [] : ['--vapi', own_fixture_directory / 'owned-resource.vapi', '--vapi', move_fixture_directory / 'move-resource.vapi']))
	endforeach
endforeach
foreach mode : ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	test('move-invalid' + mode, cli_check, args: [astrac, mode, 'move-invalid.astra', '-', 'move-invalid.stderr', '1', '--vapi', own_fixture_directory / 'owned-resource.vapi'], workdir: move_fixture_directory)
endforeach
foreach mode : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'llvm']
	test('move-basic-golden-' + mode, cli_check, args: [astrac, '--dump-' + mode, 'move-basic.astra', 'move-basic.' + (mode == 'llvm' ? 'll' : mode), '-', '0'] + (mode == 'syntax' ? [] : ['--vapi', own_fixture_directory / 'owned-resource.vapi']), workdir: move_fixture_directory)
endforeach
foreach fixture : ['conditional', 'chain', 'continue', 'both-arms', 'unreachable']
	test('move-' + fixture + '-golden-ssa', cli_check, args: [astrac, '--dump-ssa', 'move-' + fixture + '.astra', 'move-' + fixture + '.ssa', '-', '0', '--vapi', own_fixture_directory / 'owned-resource.vapi'], workdir: move_fixture_directory)
endforeach

# The same transfer/join/fixpoint cases, with nominal Resource owner values.
resource_flow_tests = executable('astra-resource-flow-tests', ['standalone.vala', 'release-standalone.vala', 'rearm-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args + ['--define=RESOURCE_HANDLES'], c_args: frontend_c_args)
test('resource-ownership-flow-standalone', resource_flow_tests, args: ['--tap'], protocol: 'tap')
