# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
infer_parser = executable('astra-infer-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
infer_semantic = executable('astra-infer-semantic', ['support.vala', 'semantic.vala'], dependencies: vapi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
infer_pipeline = executable('astra-infer-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
infer_firewall_targets = {'infer-parser': infer_parser, 'infer-semantic': infer_semantic, 'infer-pipeline': infer_pipeline}
foreach name, target : infer_firewall_targets
	test(name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
test('infer-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('infer-equivalence-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
