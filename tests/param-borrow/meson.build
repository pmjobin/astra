# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
param_borrow_semantic = executable('astra-param-borrow-semantic', ['support.vala', 'semantic.vala'], dependencies: vapi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
param_borrow_pipeline = executable('astra-param-borrow-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
param_borrow_llvm = executable('astra-param-borrow-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
param_borrow_firewall_targets = {'param-borrow-semantic': param_borrow_semantic, 'param-borrow-pipeline': param_borrow_pipeline}
foreach name, target : param_borrow_firewall_targets + {'param-borrow-llvm': param_borrow_llvm}
	test(name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
test('param-borrow-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('param-borrow-equivalence-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
