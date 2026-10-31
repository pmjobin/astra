# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

object_parser = executable('astra-object-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('object-parser', object_parser, args: ['--tap'], protocol: 'tap')
object_semantic = executable('astra-object-semantic', ['semantic-support.vala', 'semantic.vala'], dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('object-semantic', object_semantic, args: ['--tap'], protocol: 'tap')
object_borrow = executable('astra-object-borrow', ['semantic-support.vala', 'borrow.vala'], dependencies: semantic_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('object-borrow', object_borrow, args: ['--tap'], protocol: 'tap')
object_pipeline = executable('astra-object-pipeline', ['support.vala', 'pipeline.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('object-pipeline', object_pipeline, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
object_llvm = executable('astra-object-llvm', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('object-llvm', object_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
object_nabi = executable('astra-object-nabi', ['nabi-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('object-nabi-standalone', object_nabi, args: ['--tap'], protocol: 'tap')
object_firewall_targets = {'object-parser': object_parser, 'object-semantic': object_semantic, 'object-borrow': object_borrow, 'object-pipeline': object_pipeline, 'object-nabi': object_nabi}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-object-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('object-' + stage + '-standalone', target, args: ['--tap'], protocol: 'tap')
	object_firewall_targets += {'object-' + stage: target}
endforeach

object_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['basic', 'alias', 'identity', 'null', 'method', 'branch', 'branch-null', 'loop', 'lifetime', 'empty', 'nominal', 'construction-order', 'nested-construction', 'integration', 'slice', 'owned', 'order']
	foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
		test('object-' + fixture + mode, astrac, args: [mode, object_directory / 'object-' + fixture + '.astra'] + (fixture == 'owned' and mode != '--parse' and mode != '--dump-syntax' ? resource_args : []))
	endforeach
endforeach
test('object-lifetime-escape', astrac, args: ['--check', object_directory / 'object-invalid.astra'], expected_exitcode: 1)

foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	test('object-basic-golden-' + stage, cli_check, args: [astrac, '--dump-' + stage, 'object-basic.astra', 'object-basic.' + (stage == 'llvm' ? 'll' : stage), '-', '0'], workdir: object_directory)
endforeach
foreach mode : ['--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-llvm', '--check']
	test('object-invalid' + mode, cli_check, args: [astrac, mode, 'object-invalid.astra', '-', 'object-invalid.stderr', '1'], workdir: object_directory)
endforeach
foreach fixture : ['branch', 'loop']
	test('object-' + fixture + '-golden-ssa', cli_check, args: [astrac, '--dump-ssa', 'object-' + fixture + '.astra', 'object-' + fixture + '.ssa', '-', '0'], workdir: object_directory)
endforeach
test('object-empty-golden-llvm', cli_check, args: [astrac, '--dump-llvm', 'object-empty.astra', 'object-empty.ll', '-', '0'], workdir: object_directory)

test('object-native-execution', ints_python, args: [files('execute.py'), astrac, cabi_companion, meson.current_build_dir() / 'execution'], depends: [astrac, cabi_companion], workdir: meson.project_source_root(), timeout: 180)
