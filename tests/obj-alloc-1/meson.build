# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
obj_alloc_loans = executable('astra-obj-alloc-loans', 'loan-contracts.vala', dependencies: core_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-alloc-1-loan-contracts', obj_alloc_loans, args: ['--tap'], protocol: 'tap')
test('obj-alloc-1-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
