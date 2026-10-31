# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

vecmem_semantic = executable('astra-vecmem-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vecmem-semantic-standalone', vecmem_semantic, args: ['--tap'], protocol: 'tap')
vecmem_core = executable('astra-vecmem-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vecmem-core-standalone', vecmem_core, args: ['--tap'], protocol: 'tap')
vecmem_cfg = executable('astra-vecmem-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vecmem-cfg-standalone', vecmem_cfg, args: ['--tap'], protocol: 'tap')
vecmem_ssa = executable('astra-vecmem-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vecmem-ssa-standalone', vecmem_ssa, args: ['--tap'], protocol: 'tap')
vecmem_abi = executable('astra-vecmem-abi', ['abi-standalone.vala', resource_abi_mapping_sources, nabi_model_sources, cabi_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vecmem-abi-standalone', vecmem_abi, args: ['--tap'], protocol: 'tap')
vecmem_pipeline = executable('astra-vecmem-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vecmem-pipeline', vecmem_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
vecmem_llvm = executable('astra-vecmem-llvm', ['support.vala', 'llvm.vala', 'memory-test.vapi', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vecmem-llvm', vecmem_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
vecmem_firewall_targets = {'vecmem-semantic': vecmem_semantic, 'vecmem-core': vecmem_core, 'vecmem-cfg': vecmem_cfg, 'vecmem-ssa': vecmem_ssa, 'vecmem-abi': vecmem_abi, 'vecmem-pipeline': vecmem_pipeline}

vecmem_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'alias', 'call', 'null', 'f32', 'loop', 'borrow', 'lanes', 'dsp', 'dot', 'ownership', 'widths']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('vecmem-' + fixture + mode, astrac, args: [mode, vecmem_directory / 'vecmem-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('vecmem-basic-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'vecmem-basic.astra', 'vecmem-basic.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: vecmem_directory)
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('vecmem-invalid' + mode, cli_check, args: [astrac, mode, 'vecmem-invalid.astra', '-', 'vecmem-invalid.stderr', '1'], workdir: vecmem_directory)
endforeach
test('vecmem-native-execution', ints_python, args: [files('execute.py'), astrac, cabi_companion, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion], workdir: meson.project_source_root(), timeout: 300)
