# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
test('ecosystem-abi-8-debug', ints_python,
	args: [files('debug-check.py'), astrac, meson.current_build_dir() / 'debug'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
debug_proof = executable('astra-source-debug-proof', ['debug-proof.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ecosystem-abi-8-debug-proof', debug_proof, args: ['--tap'], protocol: 'tap')
test('ecosystem-abi-8-gobject', ints_python,
	args: [files('gobject-check.py'), astrac, meson.current_build_dir() / 'gobject'],
	depends: astrac, timeout: 900, workdir: meson.project_source_root())
test('ecosystem-abi-8-signals', ints_python,
	args: [files('signal-check.py'), astrac, meson.current_build_dir() / 'signals'],
	depends: astrac, timeout: 900, workdir: meson.project_source_root())
test('ecosystem-abi-8-gir', ints_python,
	args: [files('gir-check.py'), astrac, meson.current_build_dir() / 'gir'],
	depends: astrac, timeout: 900, workdir: meson.project_source_root())
module_proof = executable('astra-native-module-proof', ['module-proof.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('ecosystem-abi-8-module-proof', module_proof, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('ecosystem-abi-8-layout-contexts', ints_python,
	args: [files('layout-contexts.py'), astrac, meson.current_build_dir() / 'layout-contexts'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('ecosystem-abi-8-modules', ints_python,
	args: [files('module-check.py'), astrac, meson.current_build_dir() / 'modules'],
	depends: astrac, timeout: 900, workdir: meson.project_source_root())
test('ecosystem-abi-8-applications', ints_python,
	args: [files('apps-check.py'), astrac, meson.current_build_dir() / 'apps'],
	depends: astrac, timeout: 900, workdir: meson.project_source_root())
