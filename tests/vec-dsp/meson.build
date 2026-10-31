# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

dsp_semantic = executable('astra-dsp-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dsp-semantic-standalone', dsp_semantic, args: ['--tap'], protocol: 'tap')
dsp_core = executable('astra-dsp-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dsp-core-standalone', dsp_core, args: ['--tap'], protocol: 'tap')
dsp_cfg = executable('astra-dsp-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dsp-cfg-standalone', dsp_cfg, args: ['--tap'], protocol: 'tap')
dsp_ssa = executable('astra-dsp-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dsp-ssa-standalone', dsp_ssa, args: ['--tap'], protocol: 'tap')
dsp_values = executable('astra-dsp-values', ['values.vala', 'integer-matrix.vala', semantic_type_sources, scalar_value_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dsp-integer-value-standalone', dsp_values, args: ['--tap'], protocol: 'tap')
dsp_oracle = executable('astra-dsp-oracle', ['oracle.vala', 'integer-matrix.vala', semantic_type_sources, scalar_value_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
dsp_pipeline = executable('astra-dsp-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dsp-pipeline', dsp_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
dsp_llvm = executable('astra-dsp-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dsp-llvm', dsp_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
dsp_firewall_targets = {'dsp-semantic': dsp_semantic, 'dsp-core': dsp_core, 'dsp-cfg': dsp_cfg, 'dsp-ssa': dsp_ssa, 'dsp-values': dsp_values, 'dsp-oracle': dsp_oracle, 'dsp-pipeline': dsp_pipeline}

dsp_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['sat-scalar', 'sat-vector', 'widen', 'pack-wrap', 'pack-sat', 'interleave', 'f32', 'loop', 'order', 'ownership', 'values']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('dsp-' + fixture + mode, astrac, args: [mode, dsp_directory / 'dsp-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('dsp-values-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'dsp-values.astra', 'dsp-values.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: dsp_directory)
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('dsp-invalid' + mode, cli_check, args: [astrac, mode, 'dsp-invalid.astra', '-', 'dsp-invalid.stderr', '1'], workdir: dsp_directory)
endforeach
test('dsp-native-execution-oracle', ints_python, args: [files('execute.py'), astrac, cabi_companion, dsp_oracle, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion, dsp_oracle], workdir: meson.project_source_root(), timeout: 300)
