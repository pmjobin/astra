# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
numerical_effect_proof = executable('astra-numerical-effect-proof',
	['effects-contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: [llvm_backend_dependency, vapi_dependency],
	vala_args: frontend_vala_args, c_args: frontend_c_args)
test('numerical-optimization-11-effect-contracts', numerical_effect_proof,
	args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root(), timeout: 180)
test('numerical-optimization-11-application-a93', ints_python,
	args: [files('packets.py'), astrac, meson.current_build_dir() / 'a93'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 600,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('numerical-optimization-11-application-a94', ints_python,
	args: [files('metadata.py'), astrac, meson.current_build_dir() / 'a94'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 600,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('numerical-optimization-11-application-a95', ints_python,
	args: [files('pipeline.py'), astrac, meson.current_build_dir() / 'a95'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 600,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('numerical-optimization-11-application-a96', ints_python,
	args: [files('stream.py'), astrac, meson.current_build_dir() / 'a96'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 600,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
numerical_proof = executable('astra-numerical-proof',
	['contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: [llvm_backend_dependency, vapi_dependency],
	vala_args: frontend_vala_args, c_args: frontend_c_args)
test('numerical-optimization-11-contracts', numerical_proof, args: ['--tap'],
	protocol: 'tap', workdir: meson.project_source_root(), timeout: 180)
test('numerical-optimization-11-policies', ints_python,
	args: [files('policies.py'), astrac, meson.current_build_dir() / 'policies'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 600,
	env: ['PYTHONDONTWRITEBYTECODE=1'])

foreach app : ['85','86','87','88','89','90','91']
	test('numerical-optimization-11-application-a' + app, ints_python,
		args: [files('applications.py'), astrac, meson.current_build_dir() / ('a' + app), app],
		depends: astrac, workdir: meson.project_source_root(), timeout: 600,
		env: ['PYTHONDONTWRITEBYTECODE=1'])
endforeach

test('numerical-optimization-11-unit-policies', ints_python,
	args: [files('unit-policies.py'), astrac, meson.current_build_dir() / 'unit-policies'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 600,
	env: ['PYTHONDONTWRITEBYTECODE=1'])

numerical_memory_proof = executable('astra-numerical-memory-proof',
	['memory-contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: [llvm_backend_dependency, vapi_dependency],
	vala_args: frontend_vala_args, c_args: frontend_c_args)
test('numerical-optimization-11-memory-contracts', numerical_memory_proof,
	args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root(), timeout: 180)
test('numerical-optimization-11-memory', ints_python,
	args: [files('memory.py'), astrac, meson.current_build_dir() / 'memory'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 600,
	env: ['PYTHONDONTWRITEBYTECODE=1'])

test('numerical-optimization-11-portability', ints_python,
	args: [files('portability.py'), astrac, meson.current_build_dir() / 'portability'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 600,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
