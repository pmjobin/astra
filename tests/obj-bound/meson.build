# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
obj_bound_parser = executable('astra-obj-bound-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-bound-parser', obj_bound_parser, args: ['--tap'], protocol: 'tap')
obj_bound_semantic = executable('astra-obj-bound-semantic', ['semantic-support.vala', 'semantic.vala'], dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-bound-semantic', obj_bound_semantic, args: ['--tap'], protocol: 'tap')
obj_bound_borrow = executable('astra-obj-bound-borrow', ['semantic-support.vala', 'borrow.vala'], dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-bound-borrow', obj_bound_borrow, args: ['--tap'], protocol: 'tap')
obj_bound_pipeline = executable('astra-obj-bound-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-bound-pipeline', obj_bound_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
obj_bound_llvm = executable('astra-obj-bound-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-bound-llvm', obj_bound_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
obj_bound_nabi = executable('astra-obj-bound-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('obj-bound-nabi-standalone', obj_bound_nabi, args: ['--tap'], protocol: 'tap')
obj_bound_firewall_targets = {'obj-bound-parser': obj_bound_parser, 'obj-bound-semantic': obj_bound_semantic, 'obj-bound-borrow': obj_bound_borrow, 'obj-bound-pipeline': obj_bound_pipeline, 'obj-bound-nabi': obj_bound_nabi}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-obj-bound-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('obj-bound-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	obj_bound_firewall_targets += {'obj-bound-' + stage: target}
endforeach

obj_bound_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'mutate', 'null', 'alias', 'identity', 'copy', 'forward', 'recurse', 'method', 'struct-method', 'constructor', 'life', 'slice', 'vector', 'owned', 'owned-trap', 'empty', 'null-field', 'null-write', 'null-method']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('obj-bound-' + fixture + mode, astrac, args: [mode, obj_bound_directory / 'obj-bound-' + fixture + '.astra'] + (fixture.startswith('owned') and mode != '--parse' and mode != '--dump-syntax' ? ['--vapi', obj_life_directory / 'lifecycle.vapi'] : []))
	endforeach
endforeach
foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('obj-bound-basic-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'obj-bound-basic.astra', 'obj-bound-basic.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: obj_bound_directory)
endforeach
foreach mode : ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check']
	test('obj-bound-invalid' + mode, cli_check, args: [astrac, mode, 'obj-bound-invalid.astra', '-', 'obj-bound-invalid.stderr', '1'], workdir: obj_bound_directory)
endforeach
test('obj-bound-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: [astrac], workdir: meson.project_source_root(), timeout: 180)
