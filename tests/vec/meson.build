# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

vec_semantic = executable('astra-vec-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-semantic-standalone', vec_semantic, args: ['--tap'], protocol: 'tap')
vec_core = executable('astra-vec-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-core-standalone', vec_core, args: ['--tap'], protocol: 'tap')
vec_cfg = executable('astra-vec-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-cfg-standalone', vec_cfg, args: ['--tap'], protocol: 'tap')
vec_ssa = executable('astra-vec-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-ssa-standalone', vec_ssa, args: ['--tap'], protocol: 'tap')
vec_nabi = executable('astra-vec-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-nabi-standalone', vec_nabi, args: ['--tap'], protocol: 'tap')
vec_pipeline = executable('astra-vec-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-pipeline', vec_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
vec_llvm = executable('astra-vec-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vec-llvm', vec_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
vec_integer_oracle = executable('astra-vec-integer-oracle', ['integer-oracle.vala', semantic_type_sources, scalar_value_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
vec_firewall_targets = {'vec-semantic': vec_semantic, 'vec-core': vec_core, 'vec-cfg': vec_cfg, 'vec-ssa': vec_ssa, 'vec-nabi': vec_nabi, 'vec-pipeline': vec_pipeline, 'vec-integer-oracle': vec_integer_oracle}

vec_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'integers', 'f32', 'masks', 'branch', 'loop', 'native-call', 'order', 'ownership', 'physical']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('vec-' + fixture + mode, astrac, args: [mode, vec_directory / 'vec-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('vec-basic-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'vec-basic.astra', 'vec-basic.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: vec_directory)
endforeach
foreach fixture : ['branch', 'loop', 'masks']
	foreach stage : ['cfg', 'ssa']
		test('vec-' + fixture + '-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'vec-' + fixture + '.astra', 'vec-' + fixture + '.' + stage, '-', '0'], workdir: vec_directory)
	endforeach
endforeach
test('vec-native-call-golden-nabi', cli_check, args: [astrac, '--dump-nabi', 'vec-native-call.astra', 'vec-native-call.nabi', '-', '0'], workdir: vec_directory)
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('vec-invalid' + mode, cli_check, args: [astrac, mode, 'vec-invalid.astra', '-', 'vec-invalid.stderr', '1'], workdir: vec_directory)
endforeach
test('vec-native-execution-oracles', ints_python, args: [files('execute.py'), astrac, cabi_companion, vec_integer_oracle, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion, vec_integer_oracle], workdir: meson.project_source_root(), timeout: 180)
