# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

resource_tests = executable('astra-resource-tests', ['support.vala', 'pipeline.vala', 'diagnostics.vala', 'lifetime.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('resources', resource_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
resource_llvm_tests = executable('astra-resource-llvm-tests', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('resources-llvm', resource_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
resource_fixture_directory = meson.current_source_dir() / 'fixtures'
resource_args = ['--vapi', resource_fixture_directory / 'resource-api.vapi', '--vapi', resource_fixture_directory / 'resource-types.vapi']
foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['basic', 'unmanaged', 'borrow', 'move', 'move-null', 'release', 'rearm', 'mixed', 'order', 'null', 'phi', 'loop', 'two-types', 'extern']
		resource_fixture_args = mode == '--parse' or mode == '--dump-syntax' ? [] : resource_args
		if fixture == 'two-types' and resource_fixture_args.length() > 0
			resource_fixture_args += ['--vapi', resource_fixture_directory / 'resource-two-types.vapi']
		endif
		test('resource' + mode + '-' + fixture, astrac, args: [mode, resource_fixture_directory / 'resource-' + fixture + '.astra'] + resource_fixture_args)
	endforeach
endforeach

resource_core_standalone = executable('astra-resource-core-standalone', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('resource-core-standalone', resource_core_standalone, args: ['--tap'], protocol: 'tap')

resource_cfg_standalone = executable('astra-resource-cfg-standalone', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('resource-cfg-standalone', resource_cfg_standalone, args: ['--tap'], protocol: 'tap')

resource_ssa_standalone = executable('astra-resource-ssa-standalone', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('resource-ssa-standalone', resource_ssa_standalone, args: ['--tap'], protocol: 'tap')

resource_semantic_standalone = executable('astra-resource-semantic-standalone', 'semantic-standalone.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('resource-semantic-standalone', resource_semantic_standalone, args: ['--tap'], protocol: 'tap')
# Mapping boundary only: no VAPI, syntax, checked symbols, Core, CFG, SSA or LLVM.
resource_abi_standalone = executable('astra-resource-abi-standalone', ['abi-standalone.vala', nabi_model_sources, cabi_model_sources, ir_authority_sources] + resource_abi_mapping_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('resource-abi-standalone', resource_abi_standalone, args: ['--tap'], protocol: 'tap')

foreach mode : ['semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
	test('resource-forward-types-' + mode, cli_check, args: [astrac, '--dump-' + mode, 'resource-contract.astra', 'resource-contract.' + (mode == 'llvm' ? 'll' : mode), '-', '0', '--vapi', resource_fixture_directory / 'resource-types.vapi', '--vapi', resource_fixture_directory / 'resource-api.vapi'], workdir: resource_fixture_directory)
	test('resource-forward-api-' + mode, cli_check, args: [astrac, '--dump-' + mode, 'resource-contract.astra', 'resource-contract.' + (mode == 'llvm' ? 'll' : mode), '-', '0'] + resource_args, workdir: resource_fixture_directory)
endforeach
test('resource-contract-syntax', cli_check, args: [astrac, '--dump-syntax', 'resource-contract.astra', 'resource-contract.syntax', '-', '0'], workdir: resource_fixture_directory)

foreach mode : ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	test('resource-invalid' + mode, cli_check, args: [astrac, mode, 'resource-invalid.astra', '-', 'resource-invalid.stderr', '1', '--vapi', resource_fixture_directory / 'resource-two-types.vapi'], workdir: resource_fixture_directory)
endforeach
test('resource-invalid-vapi-cleanup', cli_check, args: [astrac, '--check', 'resource-contract.astra', '-', 'resource-invalid-vapi.stderr', '1', '--vapi', 'resource-invalid.vapi'], workdir: resource_fixture_directory)
