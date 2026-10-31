# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

ownbound_tests = executable('astra-ownbound-tests', ['support.vala', 'pipeline.vala', 'diagnostics.vala', 'lifetime.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('owned-boundaries', ownbound_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
ownbound_llvm_tests = executable('astra-ownbound-llvm-tests', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('owned-boundaries-llvm', ownbound_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
ownbound_semantic_standalone = executable('astra-ownbound-semantic-standalone', 'semantic-standalone.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ownbound-semantic-standalone', ownbound_semantic_standalone, args: ['--tap'], protocol: 'tap')
ownbound_core_standalone = executable('astra-ownbound-core-standalone', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ownbound-core-standalone', ownbound_core_standalone, args: ['--tap'], protocol: 'tap')
ownbound_cfg_standalone = executable('astra-ownbound-cfg-standalone', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ownbound-cfg-standalone', ownbound_cfg_standalone, args: ['--tap'], protocol: 'tap')
test('ownbound-ownership-flow-standalone', ownbound_cfg_standalone, args: ['--tap', '-p', '/ownbound/flow'], protocol: 'tap')
ownbound_ssa_standalone = executable('astra-ownbound-ssa-standalone', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ownbound-ssa-standalone', ownbound_ssa_standalone, args: ['--tap'], protocol: 'tap')
ownbound_abi_standalone = executable('astra-ownbound-abi-standalone', ['abi-standalone.vala', nabi_model_sources, cabi_model_sources, ir_authority_sources] + resource_abi_mapping_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ownbound-abi-standalone', ownbound_abi_standalone, args: ['--tap'], protocol: 'tap')

ownbound_directory = meson.current_source_dir() / 'fixtures'
ownbound_args = resource_args + ['--vapi', ownbound_directory / 'ownbound-extra.vapi']
foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['consume', 'pass', 'null', 'release', 'move', 'borrow', 'rearm', 'multi', 'root-order', 'nested', 'order', 'recurse', 'mutual', 'result', 'terminating', 'branches', 'loop', 'shortcircuit', 'borrow-move', 'trap']
		test('ownbound' + mode + '-' + fixture, astrac, args: [mode, ownbound_directory / 'ownbound-' + fixture + '.astra'] + (mode == '--parse' or mode == '--dump-syntax' ? [] : ownbound_args))
	endforeach
endforeach
foreach mode : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
	test('ownbound-contract-' + mode, cli_check, args: [astrac, '--dump-' + mode, 'ownbound-contract.astra', 'ownbound-contract.' + (mode == 'llvm' ? 'll' : mode), '-', '0'] + (mode == 'syntax' ? [] : ownbound_args), workdir: ownbound_directory)
endforeach
foreach mode : ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	test('ownbound-invalid' + mode, cli_check, args: [astrac, mode, 'ownbound-invalid.astra', '-', 'ownbound-invalid.stderr', '1'] + ownbound_args, workdir: ownbound_directory)
endforeach
