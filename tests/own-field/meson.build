# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
own_field_parser = executable('astra-own-field-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
own_field_semantic = executable('astra-own-field-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
own_field_pipeline = executable('astra-own-field-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
own_field_nabi = executable('astra-own-field-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
own_field_firewall_targets = {'own-field-parser': own_field_parser, 'own-field-semantic': own_field_semantic, 'own-field-pipeline': own_field_pipeline, 'own-field-nabi': own_field_nabi}
foreach name, target : own_field_firewall_targets
	test(name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-own-field-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('own-field-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	own_field_firewall_targets += {'own-field-' + stage: target}
endforeach
own_field_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'multi', 'deinit', 'borrow', 'replace', 'null', 'direct', 'result', 'generic', 'alias', 'deinit-replace', 'deinit-trap', 'rhs-trap', 'receiver-trap', 'receiver-move-trap', 'constructor-trap', 'null-object', 'branch', 'reentrant']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('own-field-' + fixture + mode, astrac, args: [mode, own_field_directory / ('own-field-' + fixture + '.astra')] + (mode == '--parse' or mode == '--dump-syntax' ? [] : ['--vapi', own_field_directory / 'resources.vapi']))
	endforeach
endforeach
test('own-field-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
test('own-field-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
own_field_llvm = executable('astra-own-field-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('own-field-llvm', own_field_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
