# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

method_parser = executable('astra-method-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('method-parser', method_parser, args: ['--tap'], protocol: 'tap')
method_semantic = executable('astra-method-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('method-semantic', method_semantic, args: ['--tap'], protocol: 'tap')
method_pipeline = executable('astra-method-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('method-pipeline', method_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
method_llvm = executable('astra-method-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('method-llvm', method_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
method_nabi = executable('astra-method-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('method-nabi-standalone', method_nabi, args: ['--tap'], protocol: 'tap')
method_firewall_targets = {'method-parser': method_parser, 'method-semantic': method_semantic, 'method-pipeline': method_pipeline, 'method-nabi': method_nabi}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-method-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('method-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	method_firewall_targets += {'method-' + stage: target}
endforeach

method_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'mutate', 'alias', 'call', 'recursive', 'vector', 'slice', 'owned', 'order']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('method-' + fixture + mode, astrac, args: [mode, method_directory / 'method-' + fixture + '.astra'] + (fixture == 'owned' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('method-basic-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'method-basic.astra', 'method-basic.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: method_directory)
endforeach
foreach mode : ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check']
	test('method-invalid' + mode, cli_check, args: [astrac, mode, 'method-invalid.astra', '-', 'method-invalid.stderr', '1'], workdir: method_directory)
endforeach
test('method-native-execution', ints_python, args: [files('execute.py'), astrac, cabi_companion, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion], workdir: meson.project_source_root(), timeout: 180)
