# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
gen_infer_semantic = executable('astra-gen-infer-semantic', ['support.vala', 'semantic.vala'], dependencies: vapi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_infer_pipeline = executable('astra-gen-infer-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_infer_firewall_targets = {'gen-infer-semantic': gen_infer_semantic, 'gen-infer-pipeline': gen_infer_pipeline}
foreach name, target : gen_infer_firewall_targets
	test(name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
test('gen-infer-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('gen-infer-equivalence-execution-permutations', ints_python, args: [files('qualify.py'), astrac, meson.current_build_dir() / 'qualification'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
