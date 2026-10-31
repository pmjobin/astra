# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
struct_agg_parser = executable('astra-struct-agg-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_agg_semantic = executable('astra-struct-agg-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_agg_firewall_targets = {'struct-agg-parser': struct_agg_parser, 'struct-agg-semantic': struct_agg_semantic}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-struct-agg-' + stage, stage + '-standalone.vala', sources, ir_authority_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('struct-agg-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	struct_agg_firewall_targets += {'struct-agg-' + stage: target}
endforeach
struct_agg_nabi = executable('astra-struct-agg-nabi', 'nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_agg_pipeline = executable('astra-struct-agg-pipeline', ['support.vala', 'pipeline.vala'], dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_agg_llvm = executable('astra-struct-agg-llvm', ['support.vala', 'llvm.vala'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
struct_agg_firewall_targets += {'struct-agg-nabi': struct_agg_nabi, 'struct-agg-pipeline': struct_agg_pipeline}
foreach name, target : {'parser': struct_agg_parser, 'semantic': struct_agg_semantic, 'nabi-standalone': struct_agg_nabi, 'pipeline': struct_agg_pipeline, 'llvm': struct_agg_llvm}
	test('struct-agg-' + name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
struct_agg_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'deep', 'siblings', 'vector', 'f64', 'pointer', 'scalarize', 'addressed', 'method', 'order', 'generic']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('struct-agg-' + fixture + mode, astrac, args: [mode, struct_agg_directory / ('struct-agg-' + fixture + '.astra')])
	endforeach
endforeach
foreach fixture : ['cycle', 'invalid']
	foreach mode : ['--check', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-llvm']
		test('struct-agg-' + fixture + mode, astrac, args: [mode, struct_agg_directory / ('struct-agg-' + fixture + '.astra')], expected_exitcode: 1)
	endforeach
endforeach
test('struct-agg-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, workdir: meson.project_source_root(), timeout: 300)
foreach fixture : ['basic', 'pointer', 'vector']
	foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
		test('struct-agg-' + fixture + '-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'struct-agg-' + fixture + '.astra', 'struct-agg-' + fixture + '.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: struct_agg_directory)
	endforeach
endforeach
