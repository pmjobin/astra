# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
struct_elements_firewall_targets = {}
struct_elements_semantic = cohort_semantic
struct_elements_nabi = cohort_nabi
struct_elements_pipeline = executable('astra-struct-elements-pipeline', ['support.vala', 'pipeline.vala'], dependencies: nabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_elements_llvm = executable('astra-struct-elements-llvm', ['support.vala', 'llvm.vala'], dependencies: [execution_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
foreach name, target : {'semantic': struct_elements_semantic, 'nabi': struct_elements_nabi, 'pipeline': struct_elements_pipeline, 'llvm': struct_elements_llvm}
	test('struct-elements-' + name, target, args: (name in ['semantic', 'nabi'] ? ['struct-elements'] : []) + ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
	if name != 'llvm'
		struct_elements_firewall_targets += {'struct-elements-' + name: target}
	endif
endforeach
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = stage == 'core' ? cohort_core : executable('astra-struct-elements-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('struct-elements-' + stage, target, args: (stage == 'core' ? ['struct-elements'] : []) + ['--tap'], protocol: 'tap')
	struct_elements_firewall_targets += {'struct-elements-' + stage: target}
endforeach
test('struct-elements-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('struct-elements-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution', stage_collector], depends: [astrac, stage_collector], timeout: 600, workdir: meson.project_source_root())
test('struct-elements-machine', ints_python, args: [files('machine.py'), meson.project_build_root(), meson.current_build_dir() / 'machine'], depends: [astrac, struct_elements_llvm], timeout: 180, workdir: meson.project_source_root())
if is_variable('diagnostic_providers')
	test('struct-elements-installed-client', ints_python, args: [files('client.py'), meson.project_build_root(), meson.current_build_dir() / 'client'], depends: [astrac, struct_elements_llvm, args_provider, text_provider] + diagnostic_providers + base_providers, is_parallel: false, timeout: 600, workdir: meson.project_source_root())
endif
