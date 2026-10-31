# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

tptr_tests = executable('astra-tptr-tests', ['support.vala', 'pipeline.vala', 'diagnostics.vala', 'lifetime.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('typed-pointers', tptr_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
tptr_llvm_tests = executable('astra-tptr-llvm-tests', ['support.vala', 'llvm.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('typed-pointers-llvm', tptr_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
tptr_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['tptr-basic', 'tptr-alias', 'tptr-null', 'tptr-recursive', 'tptr-loop', 'tptr-mixed-storage', 'tptr-order']
		test('tptr' + mode + '-' + fixture, astrac, args: [mode, tptr_fixture_directory / fixture + '.astra'])
	endforeach
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	# Historical call-bound rejection; the same source is now a safe stored borrow.
	test('tptr-now-valid-' + mode, astrac, args: [mode, tptr_fixture_directory / 'tptr-invalid.astra'])
endforeach

foreach mode : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'llvm']
	extension = mode == 'llvm' ? 'll' : mode
	test('tptr-golden-' + mode, cli_check, args: [astrac, '--dump-' + mode, 'tptr-basic.astra', 'tptr-basic.' + extension, '-', '0'], workdir: tptr_fixture_directory)
endforeach
