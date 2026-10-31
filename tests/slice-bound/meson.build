# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

slice_bound_semantic = executable('astra-slice-bound-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('slice-bound-semantic', slice_bound_semantic, args: ['--tap'], protocol: 'tap')
slice_bound_pipeline = executable('astra-slice-bound-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('slice-bound-pipeline', slice_bound_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
slice_bound_llvm = executable('astra-slice-bound-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('slice-bound-llvm', slice_bound_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
slice_bound_nabi = executable('astra-slice-bound-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('slice-bound-nabi-standalone', slice_bound_nabi, args: ['--tap'], protocol: 'tap')
slice_bound_firewall_targets = {'slice-bound-semantic': slice_bound_semantic, 'slice-bound-pipeline': slice_bound_pipeline, 'slice-bound-nabi': slice_bound_nabi}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-slice-bound-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('slice-bound-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	slice_bound_firewall_targets += {'slice-bound-' + stage: target}
endforeach

slice_bound_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['sum', 'alias', 'forward', 'merge', 'mixed', 'owned', 'bit', 'dsp', 'dot', 'owned-result']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('slice-bound-' + fixture + mode, astrac, args: [mode, slice_bound_directory / 'slice-bound-' + fixture + '.astra'] + (fixture.startswith('owned') and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('slice-bound-sum-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'slice-bound-sum.astra', 'slice-bound-sum.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: slice_bound_directory)
endforeach
test('slice-bound-native-execution', ints_python, args: [files('execute.py'), astrac, cabi_companion, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion], workdir: meson.project_source_root(), timeout: 300)
