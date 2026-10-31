# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

dot_semantic = executable('astra-dot-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dot-semantic-standalone', dot_semantic, args: ['--tap'], protocol: 'tap')
dot_core = executable('astra-dot-core', ['core-standalone.vala', core_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dot-core-standalone', dot_core, args: ['--tap'], protocol: 'tap')
dot_cfg = executable('astra-dot-cfg', ['cfg-standalone.vala', cfg_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dot-cfg-standalone', dot_cfg, args: ['--tap'], protocol: 'tap')
dot_ssa = executable('astra-dot-ssa', ['ssa-standalone.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dot-ssa-standalone', dot_ssa, args: ['--tap'], protocol: 'tap')
dot_pipeline = executable('astra-dot-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dot-pipeline', dot_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
dot_llvm = executable('astra-dot-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('dot-llvm', dot_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
dot_firewall_targets = {'dot-semantic': dot_semantic, 'dot-core': dot_core, 'dot-cfg': dot_cfg, 'dot-ssa': dot_ssa, 'dot-pipeline': dot_pipeline}

dot_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['int-basic', 'int-wrap', 'int-signedness', 'int-mac', 'f32-basic', 'f32-order', 'f32-mac', 'f32-special', 'loop', 'native', 'order', 'ownership', 'values']
	foreach mode : ['--parse', '--check', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
		test('dot-' + fixture + mode, astrac, args: [mode, dot_directory / 'dot-' + fixture + '.astra'] + (fixture == 'ownership' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('dot-values-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'dot-values.astra', 'dot-values.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: dot_directory)
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('dot-invalid' + mode, cli_check, args: [astrac, mode, 'dot-invalid.astra', '-', 'dot-invalid.stderr', '1'], workdir: dot_directory)
endforeach
test('dot-native-execution-oracle', ints_python, args: [files('execute.py'), astrac, cabi_companion, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion], workdir: meson.project_source_root(), timeout: 300)
test('dot-integer-oracle-standalone', ints_python, args: [files('oracle.py'), 'integer'], timeout: 120)
test('dot-f32-oracle-standalone', ints_python, args: [files('oracle.py'), 'f32'], timeout: 120)
