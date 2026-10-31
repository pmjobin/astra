# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
sources_parser = executable('astra-sources-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
sources_semantic = executable('astra-sources-semantic', ['support.vala', 'semantic.vala'], dependencies: vapi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
sources_pipeline = executable('astra-sources-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
sources_nabi = executable('astra-sources-nabi', ['nabi-standalone.vala', native_provenance_test_sources, nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
sources_cabi = executable('astra-sources-cabi', ['cabi-standalone.vala', cabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
sources_firewall_targets = {'sources-parser': sources_parser, 'sources-semantic': sources_semantic, 'sources-pipeline': sources_pipeline, 'sources-nabi': sources_nabi, 'sources-cabi': sources_cabi}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-sources-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	sources_firewall_targets += {'sources-' + stage: target}
endforeach
sources_llvm = executable('astra-sources-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
sources_llvm_standalone = executable('astra-sources-llvm-standalone', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources, nabi_sources, cabi_sources, llvm_backend_sources], dependencies: [host_dependencies, llvm_dependency], vala_args: frontend_vala_args + ['--define=SOURCES_LLVM'], c_args: frontend_c_args)
foreach name, target : sources_firewall_targets + {'sources-llvm': sources_llvm, 'sources-llvm-standalone': sources_llvm_standalone}
	test(name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
test('sources-composition-execution-permutations', ints_python, args: [files('qualify.py'), astrac, meson.current_build_dir() / 'qualification'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
test('sources-negative-provenance', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
