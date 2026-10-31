# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
const_semantic = executable('astra-const-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('const-semantic', const_semantic, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
const_firewall_targets = {'const-semantic': const_semantic}
const_operations = executable('astra-const-operations', 'operations.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
const_firewall_targets += {'const-operations': const_operations}
const_pipeline = executable('astra-const-pipeline', 'pipeline.vala', dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
const_llvm = executable('astra-const-llvm', 'pipeline.vala', dependencies: llvm_backend_dependency, vala_args: frontend_vala_args + ['--define=CONST_LLVM'], c_args: frontend_c_args)
const_firewall_targets += {'const-pipeline': const_pipeline}
test('const-pipeline', const_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('const-llvm-lifetimes', const_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('const-exact-oracle', ints_python, args: [files('oracle.py'), const_operations, meson.project_build_root() / 'const-1/oracle'], timeout: 600)
if is_variable('base_providers')
	test('const-composition-runtime-consumer', ints_python, args: [files('qualify.py'), astrac, meson.project_build_root() / 'const-1/qualification'], depends: [astrac] + base_providers, timeout: 600, workdir: meson.project_source_root())
endif
