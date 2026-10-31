# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

slice_semantic = executable('astra-slice-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('slice-semantic-standalone', slice_semantic, args: ['--tap'], protocol: 'tap')
slice_core = executable('astra-slice-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('slice-core-standalone', slice_core, args: ['--tap'], protocol: 'tap')
slice_cfg = executable('astra-slice-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('slice-cfg-standalone', slice_cfg, args: ['--tap'], protocol: 'tap')
slice_ssa = executable('astra-slice-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('slice-ssa-standalone', slice_ssa, args: ['--tap'], protocol: 'tap')
slice_pipeline = executable('astra-slice-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('slice-pipeline', slice_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
slice_llvm = executable('astra-slice-llvm', ['support.vala', 'llvm.vala', '../array/memory-test.vapi', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('slice-llvm', slice_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
slice_firewall_targets = {'slice-semantic': slice_semantic, 'slice-core': slice_core, 'slice-cfg': slice_cfg, 'slice-ssa': slice_ssa, 'slice-pipeline': slice_pipeline}

slice_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'subrange', 'empty', 'len', 'alias', 'branch', 'loop', 'bounds', 'order', 'f32', 'vector', 'dsp', 'ownership']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('slice-' + fixture + mode, astrac, args: [mode, slice_directory / 'slice-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('slice-basic-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'slice-basic.astra', 'slice-basic.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: slice_directory)
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('slice-invalid' + mode, cli_check, args: [astrac, mode, 'slice-invalid.astra', '-', 'slice-invalid.stderr', '1'], workdir: slice_directory)
endforeach
test('slice-native-execution', ints_python, args: [files('execute.py'), astrac, cabi_companion, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion], workdir: meson.project_source_root(), timeout: 300)
