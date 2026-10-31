# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
gen_cap_parser = executable('astra-gen-cap-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-cap-parser', gen_cap_parser, args: ['--tap'], protocol: 'tap')
gen_cap_semantic = executable('astra-gen-cap-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-cap-semantic', gen_cap_semantic, args: ['--tap'], protocol: 'tap')
gen_cap_firewall_targets = {'gen-cap-parser': gen_cap_parser, 'gen-cap-semantic': gen_cap_semantic}
foreach stage, sources : {'core': core_model_sources, 'monomorphizer': core_model_sources, 'cfg': core_model_sources + cfg_sources, 'ssa': core_model_sources + cfg_sources + ssa_sources}
	target = executable('astra-gen-cap-' + stage, ['core-support.vala', stage == 'monomorphizer' ? 'monomorphizer.vala' : stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('gen-cap-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	gen_cap_firewall_targets += {'gen-cap-' + stage: target}
endforeach
gen_cap_pipeline = executable('astra-gen-cap-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-cap-pipeline', gen_cap_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
gen_cap_llvm = executable('astra-gen-cap-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-cap-llvm', gen_cap_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
gen_cap_nabi = executable('astra-gen-cap-nabi', 'nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-cap-nabi-standalone', gen_cap_nabi, args: ['--tap'], protocol: 'tap')
gen_cap_firewall_targets += {'gen-cap-pipeline': gen_cap_pipeline, 'gen-cap-nabi': gen_cap_nabi}
gen_cap_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['eq', 'ordered', 'numeric', 'bitwise', 'shift', 'multi', 'forward', 'recursive', 'property', 'owned', 'object-owned']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('gen-cap-' + fixture + mode, astrac, args: [mode, gen_cap_directory / ('gen-cap-' + fixture + '.astra')] + (fixture == 'owned' and mode != '--parse' and mode != '--dump-syntax' ? ['--vapi', meson.project_source_root() / 'tests/obj-life/fixtures/lifecycle.vapi'] : []))
	endforeach
endforeach
test('gen-cap-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, workdir: meson.project_source_root(), timeout: 300)
foreach fixture : ['eq', 'numeric', 'multi', 'forward', 'property']
	foreach stage : ['syntax', 'semantics', 'core', 'instances', 'cfg', 'ssa', 'nabi', 'llvm']
		test('gen-cap-' + fixture + '-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'gen-cap-' + fixture + '.astra', 'gen-cap-' + fixture + '.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: gen_cap_directory)
	endforeach
endforeach
foreach mode : ['--dump-semantics', '--dump-core', '--dump-instances', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	test('gen-cap-invalid' + mode, cli_check, args: [astrac, mode, 'gen-cap-invalid.astra', '-', 'gen-cap-invalid.stderr', '1'], workdir: gen_cap_directory)
endforeach
