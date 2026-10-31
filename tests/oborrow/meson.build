# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

oborrow_tests = executable('astra-oborrow-tests', ['support.vala', 'pipeline.vala', 'diagnostics.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('owner-borrows', oborrow_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
oborrow_llvm_tests = executable('astra-oborrow-llvm-tests', ['support.vala', 'llvm.vala'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('owner-borrows-llvm', oborrow_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
oborrow_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['basic', 'native', 'forward', 'move', 'destination', 'repeated', 'null', 'loop', 'body-loop', 'continue', 'break', 'return', 'order', 'raw-null', 'extern', 'control', 'conditional', 'shortcircuit']
		test('oborrow' + mode + '-' + fixture, astrac, args: [mode, oborrow_fixture_directory / 'oborrow-' + fixture + '.astra'] + (mode == '--parse' or mode == '--dump-syntax' ? [] : ['--vapi', own_fixture_directory / 'owned-resource.vapi', '--vapi', oborrow_fixture_directory / 'borrowed-resource.vapi']))
	endforeach
endforeach
foreach mode : ['syntax', 'semantics', 'core', 'cfg', 'ssa', 'nabi', 'cabi', 'llvm']
	test('oborrow-contract-golden-' + mode, cli_check, args: [astrac, '--dump-' + mode, 'oborrow-contract.astra', 'oborrow-contract.' + (mode == 'llvm' ? 'll' : mode), '-', '0'] + (mode == 'syntax' ? [] : ['--vapi', oborrow_fixture_directory / 'contract.vapi']), workdir: oborrow_fixture_directory)
endforeach
foreach mode : ['--dump-cfg', '--dump-ssa', '--dump-cabi', '--dump-llvm', '--check']
	test('oborrow-invalid' + mode, cli_check, args: [astrac, mode, 'oborrow-invalid.astra', '-', 'oborrow-invalid.stderr', '1', '--vapi', own_fixture_directory / 'owned-resource.vapi', '--vapi', oborrow_fixture_directory / 'borrowed-resource.vapi'], workdir: oborrow_fixture_directory)
endforeach
test('oborrow-invalid-vapi', cli_check, args: [astrac, '--dump-semantics', 'oborrow-contract.astra', '-', 'borrowed-invalid.stderr', '1', '--vapi', 'borrowed-invalid.vapi'], workdir: oborrow_fixture_directory)
