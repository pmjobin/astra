# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

array_semantic = executable('astra-array-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('array-semantic-standalone', array_semantic, args: ['--tap'], protocol: 'tap')
array_core = executable('astra-array-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('array-core-standalone', array_core, args: ['--tap'], protocol: 'tap')
array_cfg = executable('astra-array-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('array-cfg-standalone', array_cfg, args: ['--tap'], protocol: 'tap')
array_ssa = executable('astra-array-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('array-ssa-standalone', array_ssa, args: ['--tap'], protocol: 'tap')
array_pipeline = executable('astra-array-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('array-pipeline', array_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
array_llvm = executable('astra-array-llvm', ['support.vala', 'llvm.vala', 'memory-test.vapi', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('array-llvm', array_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
array_firewall_targets = {'array-semantic': array_semantic, 'array-core': array_core, 'array-cfg': array_cfg, 'array-ssa': array_ssa, 'array-pipeline': array_pipeline}

array_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'index', 'bounds', 'order', 'loop', 'f32', 'vector', 'dsp', 'ownership']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('array-' + fixture + mode, astrac, args: [mode, array_directory / 'array-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('array-basic-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'array-basic.astra', 'array-basic.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: array_directory)
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('array-invalid' + mode, cli_check, args: [astrac, mode, 'array-invalid.astra', '-', 'array-invalid.stderr', '1'], workdir: array_directory)
endforeach
test('array-native-execution', ints_python, args: [files('execute.py'), astrac, cabi_companion, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion], workdir: meson.project_source_root(), timeout: 300)
