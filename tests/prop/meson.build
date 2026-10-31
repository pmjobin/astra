# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
prop_parser = executable('astra-prop-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('prop-parser', prop_parser, args: ['--tap'], protocol: 'tap')
prop_semantic = executable('astra-prop-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('prop-semantic', prop_semantic, args: ['--tap'], protocol: 'tap')
prop_pipeline = executable('astra-prop-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('prop-pipeline', prop_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
prop_llvm = executable('astra-prop-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('prop-llvm', prop_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
prop_nabi = executable('astra-prop-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('prop-nabi-standalone', prop_nabi, args: ['--tap'], protocol: 'tap')
prop_firewall_targets = {'prop-parser': prop_parser, 'prop-semantic': prop_semantic, 'prop-pipeline': prop_pipeline, 'prop-nabi': prop_nabi}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-prop-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('prop-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	prop_firewall_targets += {'prop-' + stage: target}
endforeach
prop_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'readonly', 'effect', 'null-get', 'null-set', 'alias', 'struct', 'method', 'life', 'constructor', 'owned', 'result', 'bool', 'f32', 'f64', 'vector', 'pointer', 'recursive']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('prop-' + fixture + mode, astrac, args: [mode, prop_directory / 'prop-' + fixture + '.astra'] + (fixture == 'life' and mode != '--parse' and mode != '--dump-syntax' ? ['--vapi', meson.project_source_root() / 'tests/obj-life/fixtures/lifecycle.vapi'] : []))
	endforeach
endforeach
foreach fixture : ['basic', 'f64', 'struct']
	foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
		test('prop-' + fixture + '-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'prop-' + fixture + '.astra', 'prop-' + fixture + '.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: prop_directory)
	endforeach
endforeach
foreach mode : ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	test('prop-invalid' + mode, cli_check, args: [astrac, mode, 'prop-invalid.astra', '-', 'prop-invalid.stderr', '1'], workdir: prop_directory)
endforeach
test('prop-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, workdir: meson.project_source_root(), timeout: 240)
