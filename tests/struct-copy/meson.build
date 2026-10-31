# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
struct_copy_parser = executable('astra-struct-copy-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_copy_semantic = executable('astra-struct-copy-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_copy_firewall_targets = {'struct-copy-parser': struct_copy_parser, 'struct-copy-semantic': struct_copy_semantic}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-struct-copy-' + stage, stage + '-standalone.vala', sources, ir_authority_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('struct-copy-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	struct_copy_firewall_targets += {'struct-copy-' + stage: target}
endforeach
struct_copy_nabi = executable('astra-struct-copy-nabi', 'nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_copy_pipeline = executable('astra-struct-copy-pipeline', ['support.vala', 'pipeline.vala'], dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_copy_llvm = executable('astra-struct-copy-llvm', ['support.vala', 'llvm.vala'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_copy_firewall_targets += {'struct-copy-nabi': struct_copy_nabi, 'struct-copy-pipeline': struct_copy_pipeline}
foreach name, target : {'parser': struct_copy_parser, 'semantic': struct_copy_semantic, 'nabi-standalone': struct_copy_nabi, 'pipeline': struct_copy_pipeline, 'llvm': struct_copy_llvm}
	test('struct-copy-' + name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
struct_copy_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'assign', 'nested', 'deep', 'vector', 'f64', 'pointer', 'alias', 'generic', 'scalarize', 'mixed', 'method', 'null-source', 'null-destination', 'void-pointer']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('struct-copy-' + fixture + mode, astrac, args: [mode, struct_copy_directory / ('struct-copy-' + fixture + '.astra')])
	endforeach
endforeach
foreach fixture : ['invalid']
	foreach mode : ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-llvm']
		test('struct-copy-' + fixture + mode, astrac, args: [mode, struct_copy_directory / ('struct-copy-' + fixture + '.astra')], expected_exitcode: 1)
	endforeach
endforeach
test('struct-copy-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, workdir: meson.project_source_root(), timeout: 300)
foreach fixture : ['basic', 'pointer', 'generic']
	foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
		test('struct-copy-' + fixture + '-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'struct-copy-' + fixture + '.astra', 'struct-copy-' + fixture + '.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: struct_copy_directory)
	endforeach
endforeach
