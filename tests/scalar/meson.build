# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# The reference authority builds without source, syntax, IR, or backend inputs.
scalar_reference_sources = files('reference.vala') + semantic_type_sources + scalar_value_sources
scalar_reference_tests = executable('astra-scalar-reference-tests', scalar_reference_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('scalar-reference', scalar_reference_tests, args: ['--tap'], protocol: 'tap')
scalar_tests = executable('astra-scalar-tests', 'pipeline.vala', dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('scalar-pipeline', scalar_tests, args: ['--tap'], protocol: 'tap')
scalar_firewall_targets = {'scalar-reference': scalar_reference_tests, 'scalar': scalar_tests}

# Exercise overflow boundaries under optimization and a trapping UB sanitizer.
# This is optional test instrumentation, never a production dependency/flag.
scalar_cc = meson.get_compiler('c')
scalar_ubsan_args = ['-O2', '-fstrict-overflow', '-fsanitize=undefined', '-fsanitize-undefined-trap-on-error']
if scalar_cc.has_multi_arguments(scalar_ubsan_args)
	scalar_ubsan_tests = executable('astra-scalar-ubsan-tests', scalar_reference_sources, dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args + scalar_ubsan_args)
	test('scalar-reference-ubsan', scalar_ubsan_tests, args: ['--tap'], protocol: 'tap')
	scalar_firewall_targets += {'scalar-ubsan': scalar_ubsan_tests}
endif

scalar_fixture_directory = meson.current_source_dir() / 'fixtures'
foreach fixture : ['boundaries', 'leading', 'wrapping', 'division', 'calls', 'trap-order']
	foreach mode : ['--parse', '--check']
		test('scalar-' + mode.substring(2) + '-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', '-', '0'], workdir: scalar_fixture_directory)
	endforeach
	foreach stage : ['syntax', 'semantics', 'core', 'cfg', 'ssa']
		test('scalar-' + stage + '-' + fixture, cli_check, args: [astrac, '--dump-' + stage, fixture + '.astra', fixture + '.' + stage, '-', '0'], workdir: scalar_fixture_directory)
	endforeach
endforeach
foreach fixture : ['too-large', 'too-small', 'positive-overflow', 'parenthesized-overflow', 'call-overflow', 'local-overflow', 'negative-local-overflow']
	test('scalar-parse-' + fixture, cli_check, args: [astrac, '--parse', fixture + '.astra', '-', '-', '0'], workdir: scalar_fixture_directory)
	test('scalar-syntax-' + fixture, cli_check, args: [astrac, '--dump-syntax', fixture + '.astra', fixture + '.syntax', '-', '0'], workdir: scalar_fixture_directory)
	foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa']
		test('scalar-error-' + mode.substring(2) + '-' + fixture, cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: scalar_fixture_directory)
	endforeach
endforeach

# SCALAR-1 deliberately changes historical huge-literal success into semantic
# rejection. Syntax still preserves exact digits; failures print no IR.
foreach suite, fixture : {'semantic': 'huge', 'core': 'huge', 'cfg': 'huge', 'place': 'huge-local', 'call': 'huge-argument'}
	directory = meson.project_source_root() / 'tests' / suite / 'fixtures'
	test('scalar-historical-' + suite + '-parse', cli_check, args: [astrac, '--parse', fixture + '.astra', '-', '-', '0'], workdir: directory)
	test('scalar-historical-' + suite + '-syntax', cli_check, args: [astrac, '--dump-syntax', fixture + '.astra', fixture + '.syntax', '-', '0'], workdir: directory)
	foreach mode : ['--check', '--dump-semantics', '--dump-core', '--dump-cfg', '--dump-ssa']
		test('scalar-historical-' + suite + '-' + mode.substring(2), cli_check, args: [astrac, mode, fixture + '.astra', '-', fixture + '.stderr', '1'], workdir: directory)
	endforeach
endforeach
