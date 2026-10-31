# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
gen_struct_parser = executable('astra-gen-struct-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_struct_semantic = executable('astra-gen-struct-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_struct_firewall_targets = {'gen-struct-parser': gen_struct_parser, 'gen-struct-semantic': gen_struct_semantic}
foreach stage, sources : {'core': core_model_sources, 'monomorphizer': core_model_sources, 'cfg': core_model_sources + cfg_sources, 'ssa': core_model_sources + cfg_sources + ssa_sources}
	target = executable('astra-gen-struct-' + stage, ['core-support.vala', stage == 'monomorphizer' ? 'monomorphizer.vala' : stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('gen-struct-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	gen_struct_firewall_targets += {'gen-struct-' + stage: target}
endforeach
test('gen-struct-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, workdir: meson.project_source_root(), timeout: 300)
gen_struct_nabi = executable('astra-gen-struct-nabi', 'nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_struct_pipeline = executable('astra-gen-struct-pipeline', ['support.vala', 'pipeline.vala'], dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_struct_llvm = executable('astra-gen-struct-llvm', ['support.vala', 'llvm.vala'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_struct_firewall_targets += {'gen-struct-nabi': gen_struct_nabi, 'gen-struct-pipeline': gen_struct_pipeline}
foreach name, target : {'parser': gen_struct_parser, 'semantic': gen_struct_semantic, 'nabi-standalone': gen_struct_nabi, 'pipeline': gen_struct_pipeline, 'llvm': gen_struct_llvm}
	test('gen-struct-' + name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
gen_struct_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'box-matrix', 'multi', 'phantom', 'dedup', 'generic-fn', 'cap', 'nested', 'pointer', 'f64', 'vector', 'members', 'scalarize', 'layout']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('gen-struct-' + fixture + mode, astrac, args: [mode, gen_struct_directory / ('gen-struct-' + fixture + '.astra')])
	endforeach
endforeach
foreach mode : ['--check', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-llvm']
	# Historical fixture/name retained: Box<Pair<int,int>> is now a legal plain-copy argument.
	test('gen-struct-invalid' + mode, astrac, args: [mode, gen_struct_directory / 'gen-struct-invalid.astra'], expected_exitcode: 0)
endforeach
foreach mode : ['--check', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-llvm']
	test('gen-struct-cycle' + mode, astrac, args: [mode, gen_struct_directory / 'gen-struct-cycle.astra'], expected_exitcode: 1)
endforeach
foreach fixture : ['basic', 'nested', 'generic-fn', 'cap', 'pointer']
	foreach stage : ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'llvm']
		test('gen-struct-' + fixture + '-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'gen-struct-' + fixture + '.astra', 'gen-struct-' + fixture + '.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: gen_struct_directory)
	endforeach
endforeach
