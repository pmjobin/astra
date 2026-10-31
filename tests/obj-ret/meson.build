# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

obj_ret_parser = executable('astra-obj-ret-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-ret-parser', obj_ret_parser, args: ['--tap'], protocol: 'tap')
obj_ret_semantic = executable('astra-obj-ret-semantic', ['semantic-support.vala', 'semantic.vala'], dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-ret-semantic', obj_ret_semantic, args: ['--tap'], protocol: 'tap')
obj_ret_ownership = executable('astra-obj-ret-ownership', 'ownership.vala', dependencies: cfg_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-ret-ownership-standalone', obj_ret_ownership, args: ['--tap'], protocol: 'tap')
obj_ret_pipeline = executable('astra-obj-ret-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-ret-pipeline', obj_ret_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
obj_ret_llvm = executable('astra-obj-ret-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-ret-llvm', obj_ret_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
obj_ret_nabi = executable('astra-obj-ret-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-ret-nabi-standalone', obj_ret_nabi, args: ['--tap'], protocol: 'tap')
obj_ret_firewall_targets = {'obj-ret-parser': obj_ret_parser, 'obj-ret-semantic': obj_ret_semantic, 'obj-ret-ownership': obj_ret_ownership, 'obj-ret-pipeline': obj_ret_pipeline, 'obj-ret-nabi': obj_ret_nabi}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-obj-ret-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('obj-ret-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	obj_ret_firewall_targets += {'obj-ret-' + stage: target}
endforeach
obj_ret_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'null', 'param', 'param-null', 'param-identity', 'forward', 'forward-null', 'forward-param', 'forward-consume-local', 'recursive', 'life', 'method', 'borrow', 'vector', 'slice', 'owned', 'constructor-owned', 'move', 'conditional', 'loop', 'branches', 'empty', 'no-deinit', 'argument-trap', 'constructor-trap']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('obj-ret-' + fixture + mode, astrac, args: [mode, obj_ret_directory / 'obj-ret-' + fixture + '.astra'] + (fixture == 'owned' and mode != '--parse' and mode != '--dump-syntax' ? ['--vapi', obj_life_directory / 'lifecycle.vapi'] : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('obj-ret-basic-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'obj-ret-basic.astra', 'obj-ret-basic.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: obj_ret_directory)
endforeach
foreach mode : ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check']
	test('obj-ret-invalid' + mode, cli_check, args: [astrac, mode, 'obj-ret-invalid.astra', '-', 'obj-ret-invalid.stderr', '1'], workdir: obj_ret_directory)
endforeach
test('obj-ret-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: [astrac], workdir: meson.project_source_root(), timeout: 240)
