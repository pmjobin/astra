# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
struct_abi_parser = executable('astra-struct-abi-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_abi_semantic = executable('astra-struct-abi-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_abi_firewall_targets = {'struct-abi-parser': struct_abi_parser, 'struct-abi-semantic': struct_abi_semantic}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-struct-abi-' + stage, stage + '-standalone.vala', sources, ir_authority_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('struct-abi-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	struct_abi_firewall_targets += {'struct-abi-' + stage: target}
endforeach
struct_abi_nabi = executable('astra-struct-abi-nabi', 'nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_abi_pipeline = executable('astra-struct-abi-pipeline', ['support.vala', 'pipeline.vala'], dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_abi_llvm = executable('astra-struct-abi-llvm', ['support.vala', 'llvm.vala'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_abi_firewall_targets += {'struct-abi-nabi': struct_abi_nabi, 'struct-abi-pipeline': struct_abi_pipeline}
foreach name, target : {'parser': struct_abi_parser, 'semantic': struct_abi_semantic, 'nabi-standalone': struct_abi_nabi, 'pipeline': struct_abi_pipeline, 'llvm': struct_abi_llvm}
	test('struct-abi-' + name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
struct_abi_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'identity', 'result', 'order', 'nested', 'vector', 'f32', 'f64', 'branch', 'forward', 'generic', 'single', 'cad', 'method', 'mixed', 'pointer', 'deep', 'many', 'null-source', 'null-destination']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('struct-abi-' + fixture + mode, astrac, args: [mode, struct_abi_directory / ('struct-abi-' + fixture + '.astra')])
	endforeach
endforeach
foreach fixture : ['invalid']
	foreach mode : ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-llvm']
		test('struct-abi-' + fixture + mode, astrac, args: [mode, struct_abi_directory / ('struct-abi-' + fixture + '.astra')], expected_exitcode: 1)
	endforeach
endforeach
test('struct-abi-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, workdir: meson.project_source_root(), timeout: 300)
foreach fixture : ['basic', 'nested', 'generic', 'single', 'branch', 'order']
	foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
		test('struct-abi-' + fixture + '-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'struct-abi-' + fixture + '.astra', 'struct-abi-' + fixture + '.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: struct_abi_directory)
	endforeach
endforeach
