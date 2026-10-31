# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
gen_own_parser = executable('astra-gen-own-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_own_semantic = executable('astra-gen-own-semantic', 'semantic.vala', dependencies: vapi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_own_firewall_targets = {'gen-own-parser': gen_own_parser, 'gen-own-semantic': gen_own_semantic}
foreach stage, sources : {'core': core_model_sources, 'monomorphizer': core_model_sources, 'concrete-core': core_model_sources, 'cfg': core_model_sources + cfg_sources, 'ssa': core_model_sources + cfg_sources + ssa_sources}
	target = executable('astra-gen-own-' + stage, ['core-support.vala', stage == 'monomorphizer' ? 'monomorphizer.vala' : stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('gen-own-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	gen_own_firewall_targets += {'gen-own-' + stage: target}
endforeach
gen_own_nabi = executable('astra-gen-own-nabi', 'nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_own_pipeline = executable('astra-gen-own-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_own_llvm = executable('astra-gen-own-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
gen_own_firewall_targets += {'gen-own-nabi': gen_own_nabi, 'gen-own-pipeline': gen_own_pipeline}
foreach name, target : {'parser': gen_own_parser, 'semantic': gen_own_semantic, 'nabi-standalone': gen_own_nabi, 'pipeline': gen_own_pipeline, 'llvm': gen_own_llvm}
	test('gen-own-' + name, target, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
endforeach
gen_own_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['drop-resource', 'drop-object', 'relay', 'conditional', 'recursive', 'multi', 'null', 'class-nodeinit', 'property', 'struct', 'loop', 'order', 'left-to-right', 'short-circuit', 'trap']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('gen-own-' + fixture + mode, astrac, args: [mode, gen_own_directory / ('gen-own-' + fixture + '.astra')] + (mode == '--parse' or mode == '--dump-syntax' ? [] : ['--vapi', gen_own_directory / 'ownership.vapi']))
	endforeach
endforeach
foreach mode : ['--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check']
	test('gen-own-invalid' + mode, cli_check, args: [astrac, mode, 'gen-own-invalid.astra', '-', 'gen-own-invalid.stderr', '1'], workdir: gen_own_directory)
endforeach
test('gen-own-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, workdir: meson.project_source_root(), timeout: 300)
foreach fixture : ['drop-resource', 'drop-object', 'relay', 'conditional', 'recursive', 'multi']
	foreach stage : ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'llvm']
		test('gen-own-' + fixture + '-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'gen-own-' + fixture + '.astra', 'gen-own-' + fixture + '.' + (stage == 'llvm' ? 'll' : stage), '-', '0'] + (stage == 'syntax' ? [] : ['--vapi', 'ownership.vapi']), workdir: gen_own_directory)
	endforeach
endforeach
