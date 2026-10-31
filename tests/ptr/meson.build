# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

ptr_tests = executable('astra-ptr-tests', ['support.vala', 'pipeline.vala', 'lifetime.vala', 'malformed.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('pointers', ptr_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
ptr_llvm_tests = executable('astra-ptr-llvm-tests', ['support.vala', 'llvm.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('pointers-llvm', ptr_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())

ptr_companion = custom_target('ptr-companion', input: 'companion.c', output: 'companion.o', build_by_default: true, command: [meson.get_compiler('c').cmd_array(), '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', '@INPUT@', '-o', '@OUTPUT@'])
ptr_export_companion = custom_target('ptr-export-companion', input: 'companion.c', output: 'export-companion.o', build_by_default: true, command: [meson.get_compiler('c').cmd_array(), '-std=c11', '-Wall', '-Wextra', '-Werror', '-DASTRA_TEST_PTR_EXPORT', '-c', '@INPUT@', '-o', '@OUTPUT@'])
ptr_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['ptr-native', 'ptr-null', 'ptr-merge', 'ptr-cimport', 'ptr-cexport', 'ptr-roundtrip', 'ptr-shortcircuit']
		ptr_args = [mode, ptr_fixture_directory / fixture + '.astra']
		if mode != '--parse' and mode != '--dump-syntax'
			ptr_args += ['--vapi', ptr_fixture_directory / 'pointer-alias.vapi']
		endif
		if mode != '--parse' and mode != '--dump-syntax' and (fixture == 'ptr-cexport' or fixture == 'ptr-roundtrip')
			ptr_args += ['--vapi', ptr_fixture_directory / 'pointer-roundtrip.vapi']
		endif
		test('pointers' + mode + '-' + fixture, astrac, args: ptr_args)
	endforeach
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('pointers-invalid-vapi-' + mode, astrac, args: [mode, ptr_fixture_directory / 'ptr-native.astra', '--vapi', ptr_fixture_directory / 'pointer-invalid.vapi'], expected_exitcode: 1)
endforeach
foreach mode, extension : {'--dump-nabi': 'nabi', '--dump-cabi': 'cabi'}
	test('pointers-mixed-golden-' + extension, cli_check, args: [astrac, mode, 'ptr-profiles.astra', 'ptr-profiles.' + extension, '-', '0'], workdir: ptr_fixture_directory)
endforeach
