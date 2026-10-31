# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
alloc_fail_firewall_targets = {}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-alloc-fail-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('alloc-fail-' + stage, target, args: ['--tap'], protocol: 'tap')
	alloc_fail_firewall_targets += {'alloc-fail-' + stage: target}
endforeach
alloc_fail_pipeline = executable('astra-alloc-fail-pipeline', ['support.vala', 'pipeline.vala'], dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
alloc_fail_llvm = executable('astra-alloc-fail-llvm', ['support.vala', 'llvm.vala'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('alloc-fail-pipeline', alloc_fail_pipeline, args: ['--tap'], protocol: 'tap')
test('alloc-fail-llvm', alloc_fail_llvm, args: ['--tap'], protocol: 'tap')
alloc_fail_firewall_targets += {'alloc-fail-pipeline': alloc_fail_pipeline}
test('alloc-fail-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('alloc-fail-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('alloc-fail-inventory', ints_python, args: [files('inventory.py'), astrac, meson.current_build_dir() / 'inventory'], depends: astrac, timeout: 1200, workdir: meson.project_source_root())
test('alloc-fail-machine', ints_python, args: [files('machine.py'), meson.project_build_root(), meson.current_build_dir() / 'machine'], depends: [astrac, alloc_fail_llvm], timeout: 120, workdir: meson.project_source_root())
test('alloc-fail-cad-protocol', ints_python, args: [files('../../workloads/cad/allocation_failure_boundary.py'), '--compiler', astrac, '--args-provider', args_provider, '--output', meson.current_build_dir() / 'cad-protocol'], depends: [astrac, args_provider], timeout: 120, workdir: meson.project_source_root())
test('alloc-fail-installed-client', ints_python, args: [files('client.py'), meson.project_build_root(), meson.current_build_dir() / 'client'], depends: [astrac, args_provider], timeout: 600, is_parallel: false, workdir: meson.project_source_root())
