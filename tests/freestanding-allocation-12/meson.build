# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
pc_device_proof = executable('astra-pc-device-proof',
	['device-contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: [llvm_backend_dependency, vapi_dependency],
	vala_args: frontend_vala_args, c_args: frontend_c_args)
test('freestanding-allocation-12-device-contracts', pc_device_proof,
	args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root(), timeout: 180)
allocation_proof = executable('astra-allocation-proof',
	['allocation-contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: [llvm_backend_dependency, vapi_dependency],
	vala_args: frontend_vala_args, c_args: frontend_c_args)
test('freestanding-allocation-12-allocation-contracts', allocation_proof,
	args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root(), timeout: 180)
foreach recipe : ['guest', 'devices', 'owners', 'policies', 'refusals', 'modules', 'sanitizers', 'substrate']
	test('freestanding-allocation-12-' + recipe, ints_python,
		args: [files(recipe + '.py'), astrac, meson.current_build_dir() / recipe],
		depends: astrac, workdir: meson.project_source_root(), timeout: 300,
		env: ['PYTHONDONTWRITEBYTECODE=1'])
endforeach
