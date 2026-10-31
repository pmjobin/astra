# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
cabi_fp_semantic = executable('astra-cabi-fp-semantic', ['support.vala', 'semantic.vala'], dependencies: vapi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
cabi_fp_pipeline = executable('astra-cabi-fp-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
cabi_fp_llvm = executable('astra-cabi-fp-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
cabi_fp_standalone = executable('astra-cabi-fp-standalone', ['standalone.vala', cabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
cabi_fp_firewall_targets = {'cabi-fp-semantic': cabi_fp_semantic, 'cabi-fp-pipeline': cabi_fp_pipeline, 'cabi-fp-standalone': cabi_fp_standalone}
foreach name, target : {'semantic': cabi_fp_semantic, 'pipeline': cabi_fp_pipeline, 'llvm': cabi_fp_llvm, 'standalone': cabi_fp_standalone}
	test('cabi-fp-' + name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-cabi-fp-' + stage, stage + '-standalone.vala', sources, ir_authority_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('cabi-fp-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	cabi_fp_firewall_targets += {'cabi-fp-' + stage: target}
endforeach
cabi_fp_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['cabi-f32-import', 'cabi-f32-export', 'cabi-f64-import', 'cabi-f64-export', 'cabi-fp-vapi', 'cabi-fp-mixed', 'cabi-fp-order', 'cabi-fp-trap', 'cabi-fp-trap-f32', 'cabi-fp-trap-f64', 'cabi-fp-struct-native', 'cabi-fp-arithmetic', 'cabi-fp-chain']
	foreach mode : ['--parse', '--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test(fixture + mode, astrac, args: [mode, cabi_fp_directory / (fixture + '.astra')] + (fixture == 'cabi-fp-vapi' and mode != '--parse' ? ['--vapi', cabi_fp_directory / 'cabi-fp.vapi'] : []))
	endforeach
endforeach
foreach mode : ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-cabi', '--dump-llvm']
	test('cabi-fp-invalid' + mode, astrac, args: [mode, cabi_fp_directory / 'cabi-fp-invalid.astra'], expected_exitcode: 1)
endforeach
test('cabi-fp-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
foreach fixture : ['cabi-f32-import', 'cabi-f32-export', 'cabi-f64-import', 'cabi-f64-export', 'cabi-fp-mixed', 'cabi-fp-struct-native']
	foreach stage : ['nabi', 'cabi', 'llvm']
		test(fixture + '-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, fixture + '.astra', fixture + '.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: cabi_fp_directory)
	endforeach
endforeach
