# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
gen_buffer_core = cohort_core
test('gen-buffer-core', gen_buffer_core, args: ['gen-buffer', '--tap'], protocol: 'tap')
gen_buffer_firewall_targets = {'gen-buffer-core': gen_buffer_core}
gen_buffer_semantic = executable('astra-gen-buffer-semantic', ['semantic-standalone.vala', generic_ownership_flow_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_buffer_nabi = cohort_nabi
foreach name, target : {'gen-buffer-semantic': gen_buffer_semantic, 'gen-buffer-nabi': gen_buffer_nabi}
	test(name, target, args: (name == 'gen-buffer-nabi' ? ['gen-buffer'] : []) + ['--tap'], protocol: 'tap')
	gen_buffer_firewall_targets += {name: target}
endforeach
gen_buffer_pipeline = executable('astra-gen-buffer-pipeline', ['support.vala', 'pipeline.vala'], dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_buffer_llvm = executable('astra-gen-buffer-llvm', ['support.vala', 'llvm.vala'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-buffer-pipeline', gen_buffer_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('gen-buffer-llvm', gen_buffer_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
gen_buffer_firewall_targets += {'gen-buffer-pipeline': gen_buffer_pipeline}
foreach stage, sources : {'cfg': core_model_sources + cfg_sources, 'ssa': core_model_sources + cfg_sources + ssa_sources}
	target = stage == 'cfg' ? cohort_cfg : cohort_ssa
	test('gen-buffer-' + stage, target, args: ['gen-buffer', '--tap'], protocol: 'tap')
	gen_buffer_firewall_targets += {'gen-buffer-' + stage: target}
endforeach
test('gen-buffer-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
test('gen-buffer-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution', stage_collector], depends: [astrac, stage_collector], timeout: 2700, workdir: meson.project_source_root())
test('gen-buffer-native-pairs', ints_python, args: [files('native.py'), astrac, meson.current_build_dir() / 'native'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
test('gen-buffer-cost-freestanding', ints_python, args: [files('cost.py'), astrac, meson.current_build_dir() / 'cost'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
test('gen-buffer-equivalence', ints_python, args: [files('equivalence.py'), astrac, meson.current_build_dir() / 'equivalence'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
if is_variable('diagnostic_providers')
	test('gen-buffer-installed-client', ints_python, args: [files('client.py'), meson.project_build_root(), meson.current_build_dir() / 'client', stage_collector], depends: [astrac, stage_collector, struct_elements_llvm, args_provider, text_provider] + diagnostic_providers, is_parallel: false, timeout: 600, workdir: meson.project_source_root())
endif
