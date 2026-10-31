# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

bit_semantic = executable('astra-bit-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('bit-semantic-standalone', bit_semantic, args: ['--tap'], protocol: 'tap')
bit_core = executable('astra-bit-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('bit-core-standalone', bit_core, args: ['--tap'], protocol: 'tap')
bit_cfg = executable('astra-bit-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('bit-cfg-standalone', bit_cfg, args: ['--tap'], protocol: 'tap')
bit_ssa = executable('astra-bit-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('bit-ssa-standalone', bit_ssa, args: ['--tap'], protocol: 'tap')
bit_pipeline = executable('astra-bit-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('bit-pipeline', bit_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
bit_llvm = executable('astra-bit-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('bit-llvm', bit_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
bit_firewall_targets = {'bit-semantic': bit_semantic, 'bit-core': bit_core, 'bit-cfg': bit_cfg, 'bit-ssa': bit_ssa, 'bit-pipeline': bit_pipeline}

bit_oracle_sources = files('integer-oracle.vala') + semantic_type_sources + scalar_value_sources
bit_oracle = executable('astra-bit-integer-oracle', bit_oracle_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('bit-integer-oracle-standalone', bit_oracle, args: ['--tap'], protocol: 'tap')
bit_firewall_targets += {'bit-integer-oracle': bit_oracle}
if scalar_cc.has_multi_arguments(scalar_ubsan_args)
	bit_ubsan = executable('astra-bit-integer-ubsan', bit_oracle_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args + scalar_ubsan_args)
	test('bit-integer-oracle-ubsan', bit_ubsan, args: ['--tap'], protocol: 'tap')
	bit_firewall_targets += {'bit-integer-ubsan': bit_ubsan}
endif

bit_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'signed', 'bool', 'mask', 'shift', 'shift-trap', 'vector', 'loop', 'integration', 'ownership', 'values']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('bit-' + fixture + mode, astrac, args: [mode, bit_directory / 'bit-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('bit-values-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'bit-values.astra', 'bit-values.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: bit_directory)
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('bit-invalid' + mode, cli_check, args: [astrac, mode, 'bit-invalid.astra', '-', 'bit-invalid.stderr', '1'], workdir: bit_directory)
endforeach
test('bit-native-execution-oracle', ints_python, args: [files('execute.py'), astrac, cabi_companion, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion], workdir: meson.project_source_root(), timeout: 300)
