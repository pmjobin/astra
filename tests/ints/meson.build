# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

ints_reference_sources = files('reference.vala') + semantic_type_sources + scalar_value_sources
ints_reference = executable('astra-ints-reference', ints_reference_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ints-reference', ints_reference, args: ['--tap'], protocol: 'tap')
ints_firewall_targets = {'ints-reference': ints_reference}
if scalar_cc.has_multi_arguments(scalar_ubsan_args)
	ints_ubsan = executable('astra-ints-reference-ubsan', ints_reference_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args + scalar_ubsan_args)
	test('ints-reference-ubsan', ints_ubsan, args: ['--tap'], protocol: 'tap')
	ints_firewall_targets += {'ints-reference-ubsan': ints_ubsan}
endif
ints_semantic = executable('astra-ints-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ints-semantic-standalone', ints_semantic, args: ['--tap'], protocol: 'tap')
ints_core = executable('astra-ints-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ints-core-standalone', ints_core, args: ['--tap'], protocol: 'tap')
ints_cfg = executable('astra-ints-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ints-cfg-standalone', ints_cfg, args: ['--tap'], protocol: 'tap')
ints_ssa = executable('astra-ints-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ints-ssa-standalone', ints_ssa, args: ['--tap'], protocol: 'tap')
ints_nabi = executable('astra-ints-nabi', ['nabi-standalone.vala', native_provenance_test_sources, nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ints-nabi-standalone', ints_nabi, args: ['--tap'], protocol: 'tap')
ints_pipeline = executable('astra-ints-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ints-pipeline', ints_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
ints_llvm = executable('astra-ints-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ints-llvm', ints_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
ints_firewall_targets += {'ints-semantic': ints_semantic, 'ints-core': ints_core, 'ints-cfg': ints_cfg, 'ints-ssa': ints_ssa, 'ints-nabi': ints_nabi, 'ints-pipeline': ints_pipeline}

ints_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'literals', 'wrap', 'div', 'compare', 'branch', 'loop', 'struct', 'addressable', 'native-call', 'ownership', 'physical']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('ints-' + fixture + mode, astrac, args: [mode, ints_directory / 'ints-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('ints-literals-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'ints-literals.astra', 'ints-literals.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: ints_directory)
endforeach
test('ints-native-call-golden-nabi', cli_check, args: [astrac, '--dump-nabi', 'ints-native-call.astra', 'ints-native-call.nabi', '-', '0'], workdir: ints_directory)
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('ints-invalid' + mode, cli_check, args: [astrac, mode, 'ints-invalid.astra', '-', 'ints-invalid.stderr', '1'], workdir: ints_directory)
endforeach

ints_python = find_program('python3')
test('ints-native-execution', ints_python, args: [files('execute.py'), astrac, cabi_companion, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion], workdir: meson.project_source_root(), timeout: 120)
