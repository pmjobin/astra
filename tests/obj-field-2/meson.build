# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
obj_field_contracts = executable('astra-obj-field-contracts', 'contracts.vala', dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-field-2-stage-contracts', obj_field_contracts, args: ['--tap'], protocol: 'tap')
obj_field_dependencies = [astrac]
if is_variable('async_provider')
	obj_field_dependencies += async_provider
endif
test('obj-field-2-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: obj_field_dependencies, timeout: 180, workdir: meson.project_source_root())
