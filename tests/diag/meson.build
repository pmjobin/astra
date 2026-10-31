# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
diag_semantic = executable('astra-diag-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('diag-semantic', diag_semantic, args: ['--tap'], protocol: 'tap', env: {'DIAG_OUTPUT': meson.current_build_dir() / 'semantic-output'})
diag_pipeline = executable('astra-diag-pipeline', 'pipeline.vala', dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
diag_llvm = executable('astra-diag-llvm', 'pipeline.vala', dependencies: [execution_dependency, vapi_dependency], vala_args: frontend_vala_args + ['--define=DIAG_LLVM'], c_args: frontend_c_args)
test('diag-pipeline', diag_pipeline, args: ['--tap'], protocol: 'tap')
test('diag-llvm', diag_llvm, args: ['--tap'], protocol: 'tap')
diag_firewall_targets = {'diag-semantic': diag_semantic, 'diag-pipeline': diag_pipeline}
if is_variable('diagnostic_providers')
	test('diag-source-failure-qualification', ints_python, args: [files('qualify.py'), meson.project_build_root(), meson.project_build_root() / 'diag-1/qualification'], depends: [astrac, diag_llvm] + diagnostic_providers, timeout: 600, workdir: meson.project_source_root())
	test('diag-runtime-effects-ownership', ints_python, args: [files('runtime.py'), meson.project_build_root(), meson.project_build_root() / 'diag-1/runtime'], depends: [astrac, diag_llvm, args_provider] + diagnostic_providers, timeout: 300, workdir: meson.project_source_root())
	test('diag-component-source-boundaries', ints_python, args: [files('components.py'), meson.project_build_root(), meson.project_build_root() / 'diag-1/components'], depends: [astrac, diag_llvm, args_provider] + diagnostic_providers + base_providers, timeout: 300, workdir: meson.project_source_root())
	test('diag-installed-relocated-permutations', ints_python, args: [files('install.py'), meson.project_build_root(), meson.project_build_root() / 'diag-1/installation'], depends: [astrac, args_provider, text_provider] + diagnostic_providers + base_providers, is_parallel: false, timeout: 300, workdir: meson.project_source_root())
endif
