# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
buffer_parser = executable('astra-buffer-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
buffer_semantic = executable('astra-buffer-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
buffer_pipeline = executable('astra-buffer-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, nabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
buffer_nabi = executable('astra-buffer-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
buffer_firewall_targets = {'buffer-parser': buffer_parser, 'buffer-semantic': buffer_semantic, 'buffer-pipeline': buffer_pipeline, 'buffer-nabi': buffer_nabi}
foreach name, target : buffer_firewall_targets
	test(name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-buffer-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('buffer-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	buffer_firewall_targets += {'buffer-' + stage: target}
endforeach
buffer_llvm = executable('astra-buffer-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('buffer-llvm', buffer_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('buffer-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: [astrac, buffer_llvm], timeout: 300, workdir: meson.project_source_root())
test('buffer-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
