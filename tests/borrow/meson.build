# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

borrow_tests = executable('astra-borrow-tests', ['support.vala', 'pipeline.vala', 'regions.vala', 'diagnostics.vala', 'lifetime.vala'], dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('borrows', borrow_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
borrow_llvm_tests = executable('astra-borrow-llvm-tests', ['support.vala', 'llvm.vala'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('borrows-llvm', borrow_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
borrow_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach mode : ['--parse', '--dump-syntax', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm', '--check']
	foreach fixture : ['basic', 'copy', 'reassign', 'late', 'branch', 'null', 'loop', 'scopes', 'recursive', 'transitive', 'alias', 'mixed']
		test('borrow' + mode + '-' + fixture, astrac, args: [mode, borrow_fixture_directory / 'borrow-' + fixture + '.astra'])
	endforeach
endforeach
foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa', '--dump-nabi', '--dump-cabi', '--dump-llvm']
	foreach fixture : ['invalid-if', 'invalid-loop', 'invalid-nested-loop']
		test('borrow-' + fixture + mode, cli_check, args: [astrac, mode, 'borrow-' + fixture + '.astra', '-', 'borrow-' + fixture + '.stderr', '1'], workdir: borrow_fixture_directory)
	endforeach
endforeach
foreach mode : ['core', 'cfg', 'ssa']
	test('borrow-basic-golden-' + mode, cli_check, args: [astrac, '--dump-' + mode, 'borrow-basic.astra', 'borrow-basic.' + mode, '-', '0'], workdir: borrow_fixture_directory)
endforeach
foreach fixture : ['branch', 'null', 'loop']
	test('borrow-' + fixture + '-golden-ssa', cli_check, args: [astrac, '--dump-ssa', 'borrow-' + fixture + '.astra', 'borrow-' + fixture + '.ssa', '-', '0'], workdir: borrow_fixture_directory)
endforeach
