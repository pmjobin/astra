# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
gen_copy_semantic = cohort_semantic
gen_copy_core = cohort_core
gen_copy_pipeline = executable('astra-gen-copy-pipeline', ['support.vala', 'pipeline.vala'], dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_copy_llvm = executable('astra-gen-copy-llvm', ['support.vala', 'llvm.vala'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_copy_firewall_targets = {'gen-copy-semantic': gen_copy_semantic, 'gen-copy-core': gen_copy_core, 'gen-copy-pipeline': gen_copy_pipeline}
foreach name, target : gen_copy_firewall_targets + {'gen-copy-llvm': gen_copy_llvm}
	test(name, target, args: (name in ['gen-copy-semantic', 'gen-copy-core'] ? ['gen-copy'] : []) + ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
test('gen-copy-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution', stage_collector], depends: [astrac, stage_collector], timeout: 900, workdir: meson.project_source_root())
test('gen-copy-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
test('gen-copy-equivalence', ints_python, args: [files('equivalence.py'), astrac, meson.current_build_dir() / 'equivalence'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
if is_variable('diagnostic_providers')
	test('gen-copy-installed-client', ints_python, args: [files('client.py'), meson.project_build_root(), meson.current_build_dir() / 'client', stage_collector], depends: [astrac, stage_collector, struct_elements_llvm, args_provider, text_provider] + diagnostic_providers, is_parallel: false, timeout: 600, workdir: meson.project_source_root())
endif
test('gen-copy-cost-freestanding', ints_python, args: [files('cost.py'), astrac, meson.current_build_dir() / 'cost'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
# Unsuppressed baseline/candidate memory comparison is a campaign qualification
# command (memory.py BUILD BASELINE OUTPUT), after complete suite linking.
foreach stage, sources : {'cfg': core_model_sources + cfg_sources, 'ssa': core_model_sources + cfg_sources + ssa_sources}
	target = stage == 'cfg' ? cohort_cfg : cohort_ssa
	test('gen-copy-' + stage, target, args: ['gen-copy', '--tap'], protocol: 'tap')
	gen_copy_firewall_targets += {'gen-copy-' + stage: target}
endforeach
gen_copy_nabi = cohort_nabi
test('gen-copy-nabi', gen_copy_nabi, args: ['gen-copy', '--tap'], protocol: 'tap')
gen_copy_firewall_targets += {'gen-copy-nabi': gen_copy_nabi}
