# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
text_io_frontend = executable('astra-text-io-frontend', 'frontend.vala', dependencies: vapi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('text-io-frontend', text_io_frontend, args: ['--tap'], protocol: 'tap')
text_io_pipeline = executable('astra-text-io-pipeline', 'pipeline.vala', dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
text_io_llvm = executable('astra-text-io-llvm', 'pipeline.vala', dependencies: llvm_backend_dependency, vala_args: frontend_vala_args + ['--define=TEXT_IO_LLVM'], c_args: frontend_c_args)
test('text-io-pipeline', text_io_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('text-io-llvm-lifetimes-targets', text_io_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
text_io_firewall_targets = {'text-io-frontend': text_io_frontend, 'text-io-pipeline': text_io_pipeline}
foreach stage, model : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources, 'cabi': cabi_model_sources}
	target = executable('astra-text-io-' + stage, [stage + '-standalone.vala', model, stage == 'cabi' ? nabi_provenance_sources : ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('text-io-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	text_io_firewall_targets += {'text-io-' + stage: target}
endforeach
if is_variable('text_provider')
	test('text-io-qualification', ints_python, args: [files('qualify.py'), astrac, meson.project_build_root() / 'text-io-1/qualification'], depends: [astrac, text_provider] + base_providers, timeout: 600, workdir: meson.project_source_root())
	test('text-io-installation', ints_python, args: [files('install.py'), meson.project_build_root(), meson.project_build_root() / 'text-io-1/installation'], depends: [astrac, text_provider] + base_providers, is_parallel: false, timeout: 120, workdir: meson.project_source_root())
endif
