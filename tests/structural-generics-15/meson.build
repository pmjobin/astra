# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
structural_type_arguments = executable('astra-structural-type-arguments',
	['type-arguments.vala', ir_authority_sources, generic_ownership_flow_sources],
	dependencies: host_dependencies, vala_args: frontend_vala_args,
	c_args: frontend_c_args)
test('structural-generics-15-type-arguments', structural_type_arguments,
	args: ['--tap'], protocol: 'tap')
structural_contracts = executable('astra-structural-generic-contracts', 'contracts.vala',
	dependencies: [nabi_dependency, vapi_dependency], vala_args: frontend_vala_args,
	c_args: frontend_c_args)
test('structural-generics-15-contracts', structural_contracts,
	args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
# Keep the whole-harness stress deadlines independent of concurrent compiler work.
test('structural-generics-15-execution', ints_python,
	args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 240, is_parallel: false,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('structural-generics-15-refusals', ints_python,
	args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('structural-generics-15-unit-graphs', ints_python,
	args: [files('units.py'), astrac, meson.current_build_dir() / 'unit-graphs'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 240,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('structural-generics-15-native-class-owners', ints_python,
	args: [files('native-class-owners.py'), astrac, meson.current_build_dir() / 'native-class-owners'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('structural-generics-15-resource-bounds', ints_python,
	args: [files('bounds.py'), astrac, meson.current_build_dir() / 'resource-bounds'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 360, is_parallel: false,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('structural-generics-15-historical-storage-requirements', ints_python,
	args: [files('historical-storage-requirements.py'), astrac, meson.current_build_dir() / 'historical-storage-requirements'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 360,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('structural-generics-15-historical-storage-cycles', ints_python,
	args: [files('historical-storage-cycles.py'), astrac, meson.current_build_dir() / 'historical-storage-cycles'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('structural-generics-15-historical-owner-locals', ints_python,
	args: [files('historical-owner-locals.py'), astrac, meson.current_build_dir() / 'historical-owner-locals'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 360,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('structural-generics-15-historical-observations', ints_python,
	args: ['-B', files('historical-observations.py'), astrac, meson.current_build_dir() / 'historical-observations'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 240,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('structural-generics-15-generality', ints_python,
	args: ['-B', files('generality.py'), astrac, meson.current_build_dir() / 'generality'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 240,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('structural-generics-15-code-inputs', ints_python,
	args: [files('code-inputs.py'), astrac, meson.current_build_dir() / 'code-inputs'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 240,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('structural-generics-15-async-record-equivalence', ints_python,
	args: [files('async-record-variants.py'), astrac, meson.current_build_dir() / 'async-record-equivalence'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
if get_option('linux_async')
	structural_uring_prefix = uring_dependency.get_variable(pkgconfig: 'prefix')
	test('structural-generics-15-native-Linux-tasks', ints_python,
		args: ['-B', files('task-linux.py'), astrac, structural_uring_prefix, meson.current_build_dir() / 'native-linux-tasks'],
		depends: [astrac, async_provider, async_linux_provider], workdir: meson.project_source_root(),
		timeout: 180, is_parallel: false, env: ['PYTHONDONTWRITEBYTECODE=1'])
endif
