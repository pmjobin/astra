# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

vec_lane_semantic = executable('astra-vec-lane-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-lane-semantic-standalone', vec_lane_semantic, args: ['--tap'], protocol: 'tap')
vec_lane_core = executable('astra-vec-lane-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-lane-core-standalone', vec_lane_core, args: ['--tap'], protocol: 'tap')
vec_lane_cfg = executable('astra-vec-lane-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-lane-cfg-standalone', vec_lane_cfg, args: ['--tap'], protocol: 'tap')
vec_lane_ssa = executable('astra-vec-lane-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-lane-ssa-standalone', vec_lane_ssa, args: ['--tap'], protocol: 'tap')
vec_lane_pipeline = executable('astra-vec-lane-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-lane-pipeline', vec_lane_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
vec_lane_llvm = executable('astra-vec-lane-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-lane-llvm', vec_lane_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
vec_lane_oracle = executable('astra-vec-lane-oracle', ['oracle.vala', semantic_type_sources, scalar_value_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
vec_lane_firewall_targets = {'vec-lane-semantic': vec_lane_semantic, 'vec-lane-core': vec_lane_core, 'vec-lane-cfg': vec_lane_cfg, 'vec-lane-ssa': vec_lane_ssa, 'vec-lane-pipeline': vec_lane_pipeline, 'vec-lane-oracle': vec_lane_oracle}

vec_lane_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['splat', 'extract', 'insert', 'shuffle', 'select', 'lane-f32', 'lane-loop', 'lane-ownership', 'lane-values']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('vec-lane-' + fixture + mode, astrac, args: [mode, vec_lane_directory / 'vec-' + fixture + '.astra'] + (fixture == 'lane-ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('vec-lane-values-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'vec-lane-values.astra', 'vec-lane-values.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: vec_lane_directory)
endforeach
foreach mode : ['--parse', '--dump-syntax']
	test('vec-lane-invalid' + mode, astrac, args: [mode, vec_lane_directory / 'vec-lane-invalid.astra'])
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('vec-lane-invalid' + mode, cli_check, args: [astrac, mode, 'vec-lane-invalid.astra', '-', 'vec-lane-invalid.stderr', '1'], workdir: vec_lane_directory)
endforeach
test('vec-lane-native-execution-oracle', ints_python, args: [files('execute.py'), astrac, cabi_companion, vec_lane_oracle, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion, vec_lane_oracle], workdir: meson.project_source_root(), timeout: 180)
