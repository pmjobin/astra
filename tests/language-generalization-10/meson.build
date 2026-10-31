# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
generic_contracts = executable('astra-generic-body-contracts', ['generic-contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: [llvm_backend_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-generalization-10-generic-contracts', generic_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
test('language-generalization-10-generic', ints_python, args: [files('generic.py'), astrac,
	meson.current_build_dir() / 'generic'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 240, env: ['PYTHONDONTWRITEBYTECODE=1'])
aggregate_contracts = executable('astra-aggregate-contracts', ['aggregate-contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: [llvm_backend_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-generalization-10-aggregate-contracts', aggregate_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
enum_contracts = executable('astra-enum-scalar-contracts', ['enum-contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: [llvm_backend_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-generalization-10-enum-contracts', enum_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
sequence_contracts = executable('astra-sequence-contracts', 'sequence-contracts.vala',
	dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-generalization-10-sequence-contracts', sequence_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
test('language-generalization-10-sequence', ints_python, args: [files('sequence.py'), astrac,
	meson.current_build_dir() / 'sequence'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 240, env: ['PYTHONDONTWRITEBYTECODE=1'])
test('language-generalization-10-aggregate', ints_python, args: [files('aggregate.py'), astrac,
	meson.current_build_dir() / 'aggregate'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 240, env: ['PYTHONDONTWRITEBYTECODE=1'])
test('language-generalization-10-properties', ints_python, args: [files('properties.py'), astrac,
	meson.current_build_dir() / 'properties'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 240, env: ['PYTHONDONTWRITEBYTECODE=1'])
test('language-generalization-10-nonnull', ints_python, args: [files('nonnull.py'), astrac,
	meson.current_build_dir() / 'nonnull'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 240, env: ['PYTHONDONTWRITEBYTECODE=1'])
test('language-generalization-10-descriptors', ints_python, args: [files('descriptors.py'), astrac,
	meson.current_build_dir() / 'descriptors'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 360, env: ['PYTHONDONTWRITEBYTECODE=1'])
descriptor_contracts = executable('astra-descriptor-contracts', files('descriptor-contracts.vala') + native_descriptor_sources,
	dependencies: cabi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-generalization-10-descriptor-contracts', descriptor_contracts, args: ['--tap'], protocol: 'tap',
	workdir: meson.project_source_root())
test('language-generalization-10-unicode', ints_python, args: [files('unicode.py'), astrac,
	meson.current_build_dir() / 'unicode'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 360, env: ['PYTHONDONTWRITEBYTECODE=1'])
test('language-generalization-10-record-units', ints_python, args: [files('unit-record.py'), astrac,
	meson.current_build_dir() / 'units'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 360, env: ['PYTHONDONTWRITEBYTECODE=1'])
test('language-generalization-10-generic-units', ints_python, args: [files('unit-record.py'), astrac,
	meson.current_build_dir() / 'units', 'generic'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 360, env: ['PYTHONDONTWRITEBYTECODE=1'])
test('language-generalization-10-application-a73', ints_python, args: [files('apps.py'), astrac,
	meson.current_build_dir() / 'applications', 'a73'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 360, env: ['PYTHONDONTWRITEBYTECODE=1'])
test('language-generalization-10-application-a74', ints_python, args: [files('apps.py'), astrac,
	meson.current_build_dir() / 'applications', 'a74'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 360, env: ['PYTHONDONTWRITEBYTECODE=1'])
test('language-generalization-10-application-a75', ints_python, args: [files('apps.py'), astrac,
	meson.current_build_dir() / 'applications', 'a75'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 360, env: ['PYTHONDONTWRITEBYTECODE=1'])
test('language-generalization-10-application-a76', ints_python, args: [files('apps.py'), astrac,
	meson.current_build_dir() / 'applications', 'a76'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 360, env: ['PYTHONDONTWRITEBYTECODE=1'])
foreach application : ['a77', 'a78', 'a79', 'a80', 'a81', 'a83', 'a84']
	test('language-generalization-10-application-' + application, ints_python, args: [files('apps.py'), astrac,
		meson.current_build_dir() / 'applications', application], depends: astrac,
		workdir: meson.project_source_root(), timeout: 360, env: ['PYTHONDONTWRITEBYTECODE=1'])
endforeach
test('language-generalization-10-application-a82', ints_python, args: [files('repository.py'), astrac,
	meson.current_build_dir() / 'applications'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 360, env: ['PYTHONDONTWRITEBYTECODE=1'])
test('language-generalization-10-application-boundaries', ints_python, args: [files('boundaries.py'), astrac,
	meson.current_build_dir() / 'boundaries'], depends: astrac,
	workdir: meson.project_source_root(), timeout: 240, env: ['PYTHONDONTWRITEBYTECODE=1'])
