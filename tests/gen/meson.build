# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
gen_parser = executable('astra-gen-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-parser', gen_parser, args: ['--tap'], protocol: 'tap')
gen_semantic = executable('astra-gen-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-semantic', gen_semantic, args: ['--tap'], protocol: 'tap')
gen_pipeline = executable('astra-gen-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-pipeline', gen_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
gen_llvm = executable('astra-gen-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-llvm', gen_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
gen_nabi = executable('astra-gen-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-nabi-standalone', gen_nabi, args: ['--tap'], protocol: 'tap')
gen_firewall_targets = {'gen-parser': gen_parser, 'gen-semantic': gen_semantic, 'gen-pipeline': gen_pipeline, 'gen-nabi': gen_nabi}
foreach stage, sources : {'core': core_model_sources, 'monomorphizer': core_model_sources, 'cfg': core_model_sources + cfg_sources, 'ssa': core_model_sources + cfg_sources + ssa_sources}
	target = executable('astra-gen-' + stage, ['core-support.vala', stage == 'monomorphizer' ? 'monomorphizer.vala' : stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('gen-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	gen_firewall_targets += {'gen-' + stage: target}
endforeach
gen_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['identity', 'multi', 'choose', 'loop', 'chain', 'recursive', 'mutual', 'cross', 'dedup', 'f64', 'vector', 'property', 'owned', 'object-owned', 'concrete']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('gen-' + fixture + mode, astrac, args: [mode, gen_directory / 'gen-' + fixture + '.astra'] + (fixture == 'owned' and mode != '--parse' and mode != '--dump-syntax' ? ['--vapi', meson.project_source_root() / 'tests/obj-life/fixtures/lifecycle.vapi'] : []))
	endforeach
endforeach
foreach fixture : ['identity', 'choose', 'dedup', 'property']
	foreach stage : ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'llvm']
		test('gen-' + fixture + '-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'gen-' + fixture + '.astra', 'gen-' + fixture + '.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: gen_directory)
	endforeach
endforeach
foreach mode : ['--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	test('gen-invalid' + mode, cli_check, args: [astrac, mode, 'gen-invalid.astra', '-', 'gen-invalid.stderr', '1'], workdir: gen_directory)
endforeach
test('gen-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, workdir: meson.project_source_root(), timeout: 240)
