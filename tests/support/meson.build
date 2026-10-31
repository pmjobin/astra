# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
# Each group has exactly the original model closure and host compiler options.
# The dispatcher runs one original family per process; it never combines oracles.
cohort_core = executable('astra-cohort-core', files('core-dispatch.vala') + cohort_core_tests + core_model_sources + ir_authority_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
cohort_semantic = executable('astra-cohort-semantic', files('semantic-dispatch.vala') + cohort_semantic_tests + ir_authority_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
cohort_nabi = executable('astra-cohort-nabi', files('nabi-dispatch.vala') + cohort_nabi_tests + nabi_model_sources + nabi_provenance_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
cohort_cfg = executable('astra-cohort-cfg', files('cfg-dispatch.vala') + cohort_cfg_tests + core_model_sources + cfg_sources + ir_authority_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
cohort_ssa = executable('astra-cohort-ssa', files('ssa-dispatch.vala') + cohort_ssa_tests + core_model_sources + cfg_sources + ssa_sources + ir_authority_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
stage_collector = executable('astra-stage-collector', 'stage-collector.vala', dependencies: [llvm_backend_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('shared-stage-observation-controls', find_program('python3'), args: [files('controls.py'), astrac, stage_collector, meson.current_build_dir() / 'controls'], depends: [astrac, stage_collector], timeout: 120, workdir: meson.project_source_root())
