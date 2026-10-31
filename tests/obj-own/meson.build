# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
obj_own_parser = executable('astra-obj-own-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-own-parser', obj_own_parser, args: ['--tap'], protocol: 'tap')
obj_own_semantic = executable('astra-obj-own-semantic', ['semantic-support.vala', 'semantic.vala'], dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-own-semantic', obj_own_semantic, args: ['--tap'], protocol: 'tap')
obj_own_pipeline = executable('astra-obj-own-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-own-pipeline', obj_own_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
obj_own_cleanup = executable('astra-obj-own-cleanup', 'cleanup.vala', dependencies: [vapi_dependency, cfg_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-own-cleanup-standalone', obj_own_cleanup, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
obj_own_llvm = executable('astra-obj-own-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-own-llvm', obj_own_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
obj_own_nabi = executable('astra-obj-own-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-own-nabi-standalone', obj_own_nabi, args: ['--tap'], protocol: 'tap')
obj_own_firewall_targets = {'obj-own-parser': obj_own_parser, 'obj-own-semantic': obj_own_semantic, 'obj-own-pipeline': obj_own_pipeline, 'obj-own-cleanup': obj_own_cleanup, 'obj-own-nabi': obj_own_nabi}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-obj-own-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('obj-own-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	obj_own_firewall_targets += {'obj-own-' + stage: target}
endforeach

obj_own_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'brace', 'consume', 'forward', 'conditional', 'borrow', 'null', 'borrow-alias', 'order', 'resource', 'multiple', 'method', 'constructor', 'empty', 'no-deinit', 'vector', 'slice', 'loop', 'loop-move', 'loop-local', 'fixed', 'precall-trap', 'callee-trap', 'constructor-trap', 'null-field']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('obj-own-' + fixture + mode, astrac, args: [mode, obj_own_directory / 'obj-own-' + fixture + '.astra'] + (fixture in ['resource', 'order'] and mode != '--parse' and mode != '--dump-syntax' ? ['--vapi', obj_life_directory / 'lifecycle.vapi'] : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('obj-own-consume-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'obj-own-consume.astra', 'obj-own-consume.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: obj_own_directory)
endforeach
foreach fixture, stage : {'conditional': 'ssa'}
	test('obj-own-' + fixture + '-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'obj-own-' + fixture + '.astra', 'obj-own-' + fixture + '.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: obj_own_directory)
endforeach
foreach mode : ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check']
	test('obj-own-invalid' + mode, cli_check, args: [astrac, mode, 'obj-own-invalid.astra', '-', 'obj-own-invalid.stderr', '1'], workdir: obj_own_directory)
endforeach
test('obj-own-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: [astrac], workdir: meson.project_source_root(), timeout: 240)

# PARAM-BORROW-1 supersedes the old same-owner borrow/transfer success fixture.
foreach mode : ['--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	test('obj-own-alias-overlap' + mode, cli_check, args: [astrac, mode, 'obj-own-alias.astra', '-', 'obj-own-alias.stderr', '1'], workdir: obj_own_directory)
endforeach
