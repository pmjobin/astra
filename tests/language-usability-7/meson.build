# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
usability_contracts = executable('astra-usability-contracts', 'contracts.vala',
	dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
foreach_contracts = executable('astra-foreach-contracts', 'foreach-contracts.vala',
	dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-usability-7-foreach-contracts', foreach_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
with_contracts = executable('astra-with-contracts', 'with-contracts.vala',
	dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-usability-7-with-contracts', with_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
nonnull_source_contracts = executable('astra-nonnull-source-contracts', 'nonnull-source-contracts.vala',
	dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-usability-7-nonnull-source-contracts', nonnull_source_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
nonnull_core_contracts = executable('astra-nonnull-core-contracts', 'nonnull-core-contracts.vala',
	dependencies: core_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-usability-7-nonnull-core-contracts', nonnull_core_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
nonnull_cfg_contracts = executable('astra-nonnull-cfg-contracts', 'nonnull-cfg-contracts.vala',
	dependencies: cfg_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-usability-7-nonnull-cfg-contracts', nonnull_cfg_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
nonnull_ssa_contracts = executable('astra-nonnull-ssa-contracts', 'nonnull-ssa-contracts.vala',
	dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-usability-7-nonnull-ssa-contracts', nonnull_ssa_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
nonnull_field_contracts = executable('astra-nonnull-field-contracts', 'nonnull-field-contracts.vala',
	dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-usability-7-nonnull-field-contracts', nonnull_field_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
test('language-usability-7-nonnull', ints_python, args: [files('nonnull-check.py'), astrac, args_llvm,
	meson.current_build_dir() / 'nonnull'], depends: [astrac, args_llvm], workdir: meson.project_source_root(), timeout: 240)
usability_native_contracts = executable('astra-usability-native-contracts', ['native-contracts.vala',
	'../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency,
	vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-usability-7-native-contracts', usability_native_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
test('language-usability-7-contracts', usability_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
test('language-usability-7-for', ints_python, args: [files('for-check.py'), astrac,
	meson.current_build_dir() / 'for'], workdir: meson.project_source_root(), timeout: 180)
test('language-usability-7-applications', ints_python, args: [files('apps-check.py'), astrac,
	meson.current_build_dir() / 'applications'], workdir: meson.project_source_root(), timeout: 300)
test('language-usability-7-formatter', ints_python, args: [files('formatter-check.py'), astrac,
	meson.current_build_dir() / 'formatter'], workdir: meson.project_source_root(), timeout: 240)
test('language-usability-7-numeric', ints_python, args: [files('float-check.py'), astrac, args_llvm,
	meson.current_build_dir() / 'numeric'], depends: [astrac, args_llvm],
	workdir: meson.project_source_root(), timeout: 300, env: ['PYTHONDONTWRITEBYTECODE=1'])
