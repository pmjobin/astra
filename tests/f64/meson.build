# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
f64_values = executable('astra-f64-values', ['values.vala', floating_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f64-values', f64_values, args: ['--tap'], protocol: 'tap')
f64_convert = executable('astra-f64-convert', ['convert.vala', floating_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args, override_options: numeric_oracle_overrides)
test('f64-exact-oracle', ints_python, args: [files('oracle.py'), f64_convert, meson.current_build_dir() / 'oracle-results.json'], timeout: 1200)
f64_firewall_targets = {'f64-values': f64_values, 'f64-convert': f64_convert}
if scalar_cc.has_multi_arguments(scalar_ubsan_args)
	f64_ubsan = executable('astra-f64-values-ubsan', ['values.vala', floating_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args + scalar_ubsan_args)
	test('f64-values-ubsan', f64_ubsan, args: ['--tap'], protocol: 'tap')
	f64_firewall_targets += {'f64-values-ubsan': f64_ubsan}
endif
f64_semantic = executable('astra-f64-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f64-semantic-standalone', f64_semantic, args: ['--tap'], protocol: 'tap')
f64_core = executable('astra-f64-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f64-core-standalone', f64_core, args: ['--tap'], protocol: 'tap')
f64_cfg = executable('astra-f64-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f64-cfg-standalone', f64_cfg, args: ['--tap'], protocol: 'tap')
f64_ssa = executable('astra-f64-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f64-ssa-standalone', f64_ssa, args: ['--tap'], protocol: 'tap')
f64_nabi = executable('astra-f64-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f64-nabi-standalone', f64_nabi, args: ['--tap'], protocol: 'tap')
f64_pipeline = executable('astra-f64-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f64-pipeline', f64_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
f64_llvm = executable('astra-f64-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('f64-llvm', f64_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
f64_firewall_targets += {'f64-semantic': f64_semantic, 'f64-core': f64_core, 'f64-cfg': f64_cfg, 'f64-ssa': f64_ssa, 'f64-nabi': f64_nabi, 'f64-pipeline': f64_pipeline}
f64_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'literal', 'round', 'special', 'compare', 'convert', 'call', 'loop', 'pointer', 'pointer-null', 'array', 'slice', 'object', 'ownership', 'channels']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('f64-' + fixture + mode, astrac, args: [mode, f64_directory / 'f64-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? ['--vapi', meson.project_source_root() / 'tests/obj-life/fixtures/lifecycle.vapi'] : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('f64-literal-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'f64-literal.astra', 'f64-literal.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: f64_directory)
	test('f64-convert-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'f64-convert.astra', 'f64-convert.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: f64_directory)
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('f64-invalid' + mode, cli_check, args: [astrac, mode, 'f64-invalid.astra', '-', 'f64-invalid.stderr', '1'], workdir: f64_directory)
endforeach
test('f64-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, workdir: meson.project_source_root(), timeout: 600)
