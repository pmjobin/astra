# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
num_conv_semantic = executable('astra-num-conv-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args, override_options: numeric_oracle_overrides)
num_conv_pipeline = executable('astra-num-conv-pipeline', ['support.vala', 'pipeline.vala'], dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
num_conv_firewall_targets = {'num-conv-semantic': num_conv_semantic, 'num-conv-pipeline': num_conv_pipeline}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = stage == 'core' ? cohort_core : executable('astra-num-conv-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	num_conv_firewall_targets += {'num-conv-' + stage: target}
endforeach
foreach name, target : num_conv_firewall_targets
	test(name, target, args: (name == 'num-conv-core' ? ['num-conv'] : []) + ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
num_conv_llvm = executable('astra-num-conv-llvm', ['support.vala', 'llvm.vala'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('num-conv-llvm', num_conv_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('num-conv-native-oracle', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('num-conv-suffix-oracle', ints_python, args: [files('literal-oracle.py'), num_conv_semantic, meson.current_build_dir() / 'literal-results.json'], depends: num_conv_semantic, timeout: 2400, workdir: meson.project_source_root())
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('num-conv-invalid' + mode, cli_check, args: [astrac, mode, 'num-conv-invalid.astra', '-', 'num-conv-invalid.stderr', '1'], workdir: meson.current_source_dir() / 'fixtures')
endforeach
