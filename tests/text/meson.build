# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
text_decoder = executable('astra-text-decoder', 'decoder.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('text-decoder-all-scalars', text_decoder, args: ['--tap'], protocol: 'tap', timeout: 120)
text_semantic = executable('astra-text-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('text-semantic', text_semantic, args: ['--tap'], protocol: 'tap')
text_pipeline = executable('astra-text-pipeline', 'pipeline.vala', dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
text_llvm = executable('astra-text-llvm', 'pipeline.vala', dependencies: llvm_backend_dependency, vala_args: frontend_vala_args + ['--define=TEXT_LLVM'], c_args: frontend_c_args)
test('text-pipeline', text_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('text-llvm-lifetimes', text_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
text_firewall_targets = {'text-decoder': text_decoder, 'text-semantic': text_semantic, 'text-pipeline': text_pipeline}
foreach stage, model : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources, 'nabi': nabi_model_sources}
	target = executable('astra-text-' + stage, ['standalone.vala', model, stage == 'nabi' ? nabi_provenance_sources : ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args + ['--define=TEXT_' + stage.to_upper()], c_args: frontend_c_args)
	test('text-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	text_firewall_targets += {'text-' + stage: target}
endforeach

foreach stage : ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
	test('text-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'basics.astra', 'basics.' + stage, '-', '0'], workdir: meson.current_source_dir() / 'fixtures')
endforeach
if is_variable('base_providers')
	test('text-qualification', ints_python, args: [files('qualify.py'), astrac, meson.project_build_root() / 'text-1/qualification'], depends: [astrac] + base_providers, timeout: 600, workdir: meson.project_source_root())
endif
