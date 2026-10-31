# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
baselib_pipeline = executable('astra-baselib-pipeline', 'pipeline.vala', dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
baselib_llvm = executable('astra-baselib-llvm', 'pipeline.vala', dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args + ['--define=BASELIB_LLVM'], c_args: frontend_c_args)
baselib_link_inputs = executable('astra-baselib-link-inputs', ['link-inputs.vala', host_linker_sources, linker_config_source], dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
baselib_firewall_targets = {'baselib-pipeline': baselib_pipeline, 'baselib-link-inputs': baselib_link_inputs}
test('baselib-pipeline', baselib_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('baselib-llvm-lifetimes', baselib_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('baselib-link-inputs', baselib_link_inputs, args: [cabi_record_linker, meson.current_build_dir() / 'link-inputs.txt', '--tap'], protocol: 'tap', workdir: meson.project_source_root())
if is_variable('base_providers')
	test('baselib-numerical-contracts', ints_python, args: [files('qualify.py'), astrac, meson.current_build_dir() / 'qualification'], depends: [astrac] + base_providers, timeout: 300, workdir: meson.project_source_root())
	test('baselib-driver-install-consumption', ints_python, args: [files('integration.py'), meson.project_build_root(), meson.current_build_dir() / 'integration'], depends: [astrac] + base_providers, timeout: 180, workdir: meson.project_source_root())
endif
