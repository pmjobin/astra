# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

f32_value_sources = files('values.vala') + f32_authority_sources
f32_values = executable('astra-f32-values', f32_value_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f32-values', f32_values, args: ['--tap'], protocol: 'tap')
f32_firewall_targets = {'f32-values': f32_values}
if scalar_cc.has_multi_arguments(scalar_ubsan_args)
	f32_ubsan = executable('astra-f32-values-ubsan', f32_value_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args + scalar_ubsan_args)
	test('f32-values-ubsan', f32_ubsan, args: ['--tap'], protocol: 'tap')
	f32_firewall_targets += {'f32-values-ubsan': f32_ubsan}
endif
f32_convert = executable('astra-f32-convert', files('convert.vala') + f32_authority_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
f32_oracle = executable('astra-f32-libc-oracle', 'oracle.c', dependencies: scalar_cc.find_library('m'))
test('f32-decimal-oracles', ints_python, args: [files('oracle.py'), f32_convert, f32_oracle, meson.current_build_dir() / 'oracle-results.json'], timeout: 120)
f32_semantic = executable('astra-f32-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f32-semantic-standalone', f32_semantic, args: ['--tap'], protocol: 'tap')
f32_core = executable('astra-f32-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f32-core-standalone', f32_core, args: ['--tap'], protocol: 'tap')
f32_cfg = executable('astra-f32-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f32-cfg-standalone', f32_cfg, args: ['--tap'], protocol: 'tap')
f32_ssa = executable('astra-f32-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f32-ssa-standalone', f32_ssa, args: ['--tap'], protocol: 'tap')
f32_nabi = executable('astra-f32-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f32-nabi-standalone', f32_nabi, args: ['--tap'], protocol: 'tap')
f32_pipeline = executable('astra-f32-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f32-pipeline', f32_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
f32_llvm = executable('astra-f32-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f32-llvm', f32_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
f32_firewall_targets += {'f32-convert': f32_convert, 'f32-semantic': f32_semantic, 'f32-core': f32_core, 'f32-cfg': f32_cfg, 'f32-ssa': f32_ssa, 'f32-nabi': f32_nabi, 'f32-pipeline': f32_pipeline}

f32_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'literals', 'special', 'rounding', 'compare', 'branch', 'loop', 'struct', 'addressable', 'native-call', 'ownership', 'physical']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('f32-' + fixture + mode, astrac, args: [mode, f32_directory / 'f32-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('f32-literals-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'f32-literals.astra', 'f32-literals.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: f32_directory)
endforeach
test('f32-native-call-golden-nabi', cli_check, args: [astrac, '--dump-nabi', 'f32-native-call.astra', 'f32-native-call.nabi', '-', '0'], workdir: f32_directory)
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('f32-invalid' + mode, cli_check, args: [astrac, mode, 'f32-invalid.astra', '-', 'f32-invalid.stderr', '1'], workdir: f32_directory)
endforeach
test('f32-native-execution', ints_python, args: [files('execute.py'), astrac, cabi_companion, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion], workdir: meson.project_source_root(), timeout: 120)
