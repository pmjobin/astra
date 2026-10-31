# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
args_semantic = executable('astra-args-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('args-semantic', args_semantic, args: ['--tap'], protocol: 'tap')
args_pipeline = executable('astra-args-pipeline', 'pipeline.vala', dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
args_llvm = executable('astra-args-llvm', 'pipeline.vala', dependencies: [execution_dependency, vapi_dependency], vala_args: frontend_vala_args + ['--define=ARGS_LLVM'], c_args: frontend_c_args)
test('args-pipeline', args_pipeline, args: ['--tap'], protocol: 'tap')
test('args-llvm', args_llvm, args: ['--tap'], protocol: 'tap')
args_firewall_targets = {'args-semantic': args_semantic, 'args-pipeline': args_pipeline}
foreach stage, model : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources, 'nabi': nabi_model_sources}
	target = executable('astra-args-' + stage, ['standalone.vala', model, stage == 'nabi' ? nabi_provenance_sources : ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args + ['--define=ARGS_' + stage.to_upper()], c_args: frontend_c_args)
	test('args-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	args_firewall_targets += {'args-' + stage: target}
endforeach
if is_variable('args_provider')
	test('args-effects', ints_python, args: [files('effects.py'), meson.project_build_root(), meson.project_build_root() / 'args-1/effects'], depends: [astrac, args_llvm, args_provider, text_provider], timeout: 600, workdir: meson.project_source_root())
	test('args-installation', ints_python, args: [files('install.py'), meson.project_build_root(), meson.project_build_root() / 'args-1/installation'], depends: [astrac, args_provider, text_provider] + base_providers, is_parallel: false, timeout: 300, workdir: meson.project_source_root())
	test('args-qualification', ints_python, args: [files('qualify.py'), astrac, meson.project_build_root() / 'args-1/qualification'], depends: [astrac, args_provider, text_provider], timeout: 900, workdir: meson.project_source_root())
endif

foreach stage : ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
	test('args-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'golden.astra', 'golden.' + stage, '-', '0'], workdir: meson.current_source_dir() / 'fixtures')
endforeach
