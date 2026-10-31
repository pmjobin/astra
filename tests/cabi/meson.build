# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# Test-only relocatable objects. No C header discovery or compiler invocation
# is part of Astra's declaration or lowering pipeline.
cabi_companion = custom_target('cabi-companion', input: 'companion.c', output: 'companion.o', build_by_default: true, command: [meson.get_compiler('c').cmd_array(), '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', '@INPUT@', '-o', '@OUTPUT@'])
cabi_second = custom_target('cabi-second', input: 'second.c', output: 'second.o', build_by_default: true, command: [meson.get_compiler('c').cmd_array(), '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', '@INPUT@', '-o', '@OUTPUT@'])

cabi_tests = executable('astra-cabi-tests', ['pipeline.vala', 'malformed.vala', 'exports.vala', 'export-malformed.vala'], dependencies: [cabi_dependency, nabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('cabi', cabi_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())

# Only physical C ABI model/verifier/dumper, generic foreign metadata and provenance.
cabi_standalone_tests = executable('astra-cabi-standalone-tests', ['standalone.vala', 'standalone-exports.vala', 'standalone-metadata.vala', 'standalone-owned.vala', cabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('cabi-standalone', cabi_standalone_tests, args: ['--tap'], protocol: 'tap')

cabi_record_linker = executable('astra-cabi-record-linker', 'record-linker.vala', dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)

cabi_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach mode : ['--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['c-basic', 'c-void', 'c-order', 'c-shortcircuit', 'c-loop', 'c-recursive-native', 'c-missing-symbol', 'c-trap-order']
		test('cabi' + mode + '-' + fixture, astrac, args: [mode, cabi_fixture_directory / fixture + '.astra'])
	endforeach
endforeach

foreach mode, extension : {'--dump-nabi': 'nabi', '--dump-cabi': 'cabi', '--dump-llvm': 'll'}
	test('cabi-golden-' + extension, cli_check, args: [astrac, mode, 'c-basic.astra', 'c-basic.' + extension, '-', '0'], workdir: cabi_fixture_directory)
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('cabi-bool-rejected-' + mode, astrac, args: [mode, cabi_fixture_directory / 'c-invalid-bool.astra'], expected_exitcode: 1)
endforeach
test('cabi-missing-argument', astrac, args: ['--dump-cabi'], expected_exitcode: 2)
test('cabi-duplicate-source', astrac, args: ['--dump-cabi', 'first.astra', './first.astra'], expected_exitcode: 2)

# Separate companion variants keep earlier import-only links independent.
cexport_objects = []
foreach variant : range(1, 8)
	cexport_objects += custom_target('cexport-companion-' + variant.to_string(), input: 'companion.c', output: 'cexport-companion-' + variant.to_string() + '.o', build_by_default: true, command: [meson.get_compiler('c').cmd_array(), '-std=c11', '-Wall', '-Wextra', '-Werror', '-DASTRA_TEST_CEXPORT=' + variant.to_string(), '-c', '@INPUT@', '-o', '@OUTPUT@'])
endforeach

cexport_fixtures = ['cexport-basic', 'cexport-void', 'cexport-native-call', 'cexport-recursive', 'cexport-roundtrip', 'cexport-shortcircuit', 'cexport-body', 'cexport-trap', 'cexport-main']
foreach mode : ['--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : cexport_fixtures
		test('cexport' + mode + '-' + fixture, astrac, args: [mode, cabi_fixture_directory / fixture + '.astra'])
	endforeach
endforeach
foreach mode, extension : {'--dump-nabi': 'nabi', '--dump-cabi': 'cabi', '--dump-llvm': 'll'}
	test('cexport-golden-' + extension, cli_check, args: [astrac, mode, 'cexport-native-call.astra', 'cexport-native-call.' + extension, '-', '0'], workdir: cabi_fixture_directory)
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('cexport-bool-rejected-' + mode, cli_check, args: [astrac, mode, 'cexport-invalid-bool.astra', '-', 'cexport-invalid-bool.stderr', '1'], workdir: cabi_fixture_directory)
endforeach
