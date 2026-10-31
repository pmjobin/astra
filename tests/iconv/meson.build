# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

iconv_semantic = executable('astra-iconv-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('iconv-semantic-standalone', iconv_semantic, args: ['--tap'], protocol: 'tap')
iconv_core = executable('astra-iconv-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('iconv-core-standalone', iconv_core, args: ['--tap'], protocol: 'tap')
iconv_cfg = executable('astra-iconv-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('iconv-cfg-standalone', iconv_cfg, args: ['--tap'], protocol: 'tap')
iconv_ssa = executable('astra-iconv-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('iconv-ssa-standalone', iconv_ssa, args: ['--tap'], protocol: 'tap')
iconv_firewall_targets = {'iconv-semantic': iconv_semantic, 'iconv-core': iconv_core, 'iconv-cfg': iconv_cfg, 'iconv-ssa': iconv_ssa}

iconv_oracle = executable('astra-iconv-oracle', ['values.vala', semantic_type_sources, scalar_value_sources, integer_conversion_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('iconv-integer-value-standalone', iconv_oracle, args: ['--tap'], protocol: 'tap')
iconv_pipeline = executable('astra-iconv-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('iconv-pipeline', iconv_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
iconv_llvm = executable('astra-iconv-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('iconv-llvm', iconv_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
iconv_firewall_targets += {'iconv-oracle': iconv_oracle, 'iconv-pipeline': iconv_pipeline}

iconv_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['scalar', 'vector', 'control', 'fields', 'ownership', 'values']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('iconv-' + fixture + mode, astrac, args: [mode, iconv_directory / 'iconv-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('iconv-values-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'iconv-values.astra', 'iconv-values.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: iconv_directory)
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('iconv-invalid' + mode, cli_check, args: [astrac, mode, 'iconv-invalid.astra', '-', 'iconv-invalid.stderr', '1'], workdir: iconv_directory)
endforeach
test('iconv-native-execution-oracle', ints_python, args: [files('execute.py'), astrac, cabi_companion, iconv_oracle, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion, iconv_oracle], workdir: meson.project_source_root(), timeout: 240)
