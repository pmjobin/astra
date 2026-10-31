# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

dptr_semantic = executable('astra-dptr-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dptr-semantic-standalone', dptr_semantic, args: ['--tap'], protocol: 'tap')
dptr_core = executable('astra-dptr-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dptr-core-standalone', dptr_core, args: ['--tap'], protocol: 'tap')
dptr_cfg = executable('astra-dptr-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dptr-cfg-standalone', dptr_cfg, args: ['--tap'], protocol: 'tap')
dptr_ssa = executable('astra-dptr-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dptr-ssa-standalone', dptr_ssa, args: ['--tap'], protocol: 'tap')
dptr_abi = executable('astra-dptr-abi', ['abi-standalone.vala', resource_abi_mapping_sources, nabi_model_sources, cabi_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dptr-abi-standalone', dptr_abi, args: ['--tap'], protocol: 'tap')
dptr_pipeline = executable('astra-dptr-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dptr-pipeline', dptr_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
dptr_llvm = executable('astra-dptr-llvm', ['support.vala', 'llvm.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dptr-llvm', dptr_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
dptr_firewall_targets = {'dptr-semantic': dptr_semantic, 'dptr-core': dptr_core, 'dptr-cfg': dptr_cfg, 'dptr-ssa': dptr_ssa, 'dptr-abi': dptr_abi, 'dptr-pipeline': dptr_pipeline}

dptr_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'alias', 'call', 'null', 'f32', 'loop', 'borrow', 'integration', 'ownership', 'widths']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('dptr-' + fixture + mode, astrac, args: [mode, dptr_directory / 'dptr-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('dptr-basic-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'dptr-basic.astra', 'dptr-basic.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: dptr_directory)
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('dptr-invalid' + mode, cli_check, args: [astrac, mode, 'dptr-invalid.astra', '-', 'dptr-invalid.stderr', '1'], workdir: dptr_directory)
endforeach
test('dptr-native-execution', ints_python, args: [files('execute.py'), astrac, cabi_companion, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion], workdir: meson.project_source_root(), timeout: 300)
