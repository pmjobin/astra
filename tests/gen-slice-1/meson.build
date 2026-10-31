# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
gen_slice_semantic = cohort_semantic
gen_slice_core = cohort_core
gen_slice_pipeline = executable('astra-gen-slice-pipeline', ['support.vala', 'pipeline.vala'], dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_slice_llvm = executable('astra-gen-slice-llvm', ['support.vala', 'llvm.vala'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_slice_firewall_targets = {'gen-slice-semantic': gen_slice_semantic, 'gen-slice-core': gen_slice_core, 'gen-slice-pipeline': gen_slice_pipeline}
foreach name, target : gen_slice_firewall_targets + {'gen-slice-llvm': gen_slice_llvm}
	test(name, target, args: (name in ['gen-slice-semantic', 'gen-slice-core'] ? ['gen-slice'] : []) + ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
test('gen-slice-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution', stage_collector], depends: [astrac, stage_collector], timeout: 900, workdir: meson.project_source_root())
test('gen-slice-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
test('gen-slice-equivalence', ints_python, args: [files('equivalence.py'), astrac, meson.current_build_dir() / 'equivalence'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
if is_variable('diagnostic_providers')
	test('gen-slice-installed-client', ints_python, args: [files('client.py'), meson.project_build_root(), meson.current_build_dir() / 'client', stage_collector], depends: [astrac, stage_collector, struct_elements_llvm, args_provider, text_provider] + diagnostic_providers, is_parallel: false, timeout: 600, workdir: meson.project_source_root())
endif
test('gen-slice-cost-freestanding', ints_python, args: [files('cost.py'), astrac, meson.current_build_dir() / 'cost'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
# Unsuppressed baseline/candidate memory comparison is a campaign qualification
# command (memory.py BUILD BASELINE OUTPUT), after complete suite linking.
foreach stage, sources : {'cfg': core_model_sources + cfg_sources, 'ssa': core_model_sources + cfg_sources + ssa_sources}
	target = executable('astra-gen-slice-' + stage, ['gen-slice-support.vala', stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('gen-slice-' + stage, target, args: ['--tap'], protocol: 'tap')
	gen_slice_firewall_targets += {'gen-slice-' + stage: target}
endforeach
gen_slice_nabi = executable('astra-gen-slice-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-slice-nabi', gen_slice_nabi, args: ['--tap'], protocol: 'tap')
gen_slice_firewall_targets += {'gen-slice-nabi': gen_slice_nabi}
