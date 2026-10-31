# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

obj_life_parser = executable('astra-obj-life-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-life-parser', obj_life_parser, args: ['--tap'], protocol: 'tap')
obj_life_semantic = executable('astra-obj-life-semantic', 'semantic.vala', dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-life-semantic', obj_life_semantic, args: ['--tap'], protocol: 'tap')
obj_life_init = executable('astra-obj-life-init-analysis', ['init-analysis-standalone.vala', field_initialization_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-life-init-analysis-standalone', obj_life_init, args: ['--tap'], protocol: 'tap')
obj_life_pipeline = executable('astra-obj-life-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-life-pipeline', obj_life_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
obj_life_llvm = executable('astra-obj-life-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-life-llvm', obj_life_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
obj_life_nabi = executable('astra-obj-life-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-life-nabi-standalone', obj_life_nabi, args: ['--tap'], protocol: 'tap')
obj_life_firewall_targets = {'obj-life-parser': obj_life_parser, 'obj-life-semantic': obj_life_semantic, 'obj-life-init-analysis': obj_life_init, 'obj-life-pipeline': obj_life_pipeline, 'obj-life-nabi': obj_life_nabi}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-obj-life-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('obj-life-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	obj_life_firewall_targets += {'obj-life-' + stage: target}
endforeach

obj_life_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['init', 'init-branch', 'init-unreachable', 'constructor-local', 'deinit', 'alias', 'rebind', 'null-rebind', 'order', 'return', 'loop', 'return-loop', 'empty', 'brace', 'vector', 'slice', 'owned', 'owned-argument-trap', 'argument-trap', 'constructor-trap', 'destructor-trap', 'brace-trap', 'post-construction-trap']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('obj-life-' + fixture + mode, astrac, args: [mode, obj_life_directory / 'obj-life-' + fixture + '.astra'] + (mode == '--parse' or mode == '--dump-syntax' ? [] : ['--vapi', obj_life_directory / 'lifecycle.vapi']))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('obj-life-alias-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'obj-life-alias.astra', 'obj-life-alias.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: obj_life_directory)
endforeach
foreach mode : ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check']
	test('obj-life-invalid' + mode, cli_check, args: [astrac, mode, 'obj-life-init-invalid.astra', '-', 'obj-life-init-invalid.stderr', '1'], workdir: obj_life_directory)
endforeach

test('obj-life-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: [astrac], workdir: meson.project_source_root(), timeout: 180)
