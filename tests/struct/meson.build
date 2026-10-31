# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

struct_tests = executable('astra-struct-tests', ['support.vala', 'pipeline.vala', 'diagnostics.vala', 'lifetime.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('structs', struct_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
struct_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['struct-basic', 'struct-order', 'struct-branch', 'struct-loop', 'struct-pointer', 'struct-scope', 'struct-trap']
		test('structs' + mode + '-' + fixture, astrac, args: [mode, struct_fixture_directory / fixture + '.astra'])
	endforeach
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	test('structs-invalid-' + mode, astrac, args: [mode, struct_fixture_directory / 'struct-invalid.astra'], expected_exitcode: 1)
endforeach

struct_llvm_tests = executable('astra-struct-llvm-tests', ['support.vala', 'llvm.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('structs-llvm', struct_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())

foreach mode : ['syntax', 'semantics', 'core', 'cfg', 'ssa']
	fixture = mode == 'syntax' or mode == 'semantics' ? 'struct-basic' : 'struct-branch'
	test('structs-golden-' + mode, cli_check, args: [astrac, '--dump-' + mode, fixture + '.astra', fixture + '.' + mode, '-', '0'], workdir: struct_fixture_directory)
endforeach
