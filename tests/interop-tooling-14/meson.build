# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
test('interop-tooling-14-packages', ints_python,
	args: [files('packages.py'), astrac, meson.current_build_dir() / 'packages'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-lsp', ints_python,
	args: [files('lsp.py'), astrac, meson.current_build_dir() / 'lsp'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-policy-registry', ints_python,
	args: [files('policy-registry.py'), astrac, meson.current_build_dir() / 'policies'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-c-policies', ints_python,
	args: [files('c-policies.py'), astrac, meson.current_build_dir() / 'c-policies'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
windows_interop_proof = executable('astra-windows-interop-proof',
	['windows-profile.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: execution_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('interop-tooling-14-windows-profile', windows_interop_proof, args: ['--tap'], protocol: 'tap')
test('interop-tooling-14-c-class', ints_python,
	args: [files('c-class.py'), astrac, meson.current_build_dir() / 'c-class'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
c_class_proof = executable('astra-foreign-class-proof',
	['c-class-contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('interop-tooling-14-c-class-contracts', c_class_proof, args: ['--tap'], protocol: 'tap')
test('interop-tooling-14-c-pointers', ints_python,
	args: [files('c-pointers.py'), astrac, meson.current_build_dir() / 'c-pointers'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-c-owners', ints_python,
	args: [files('c-owners.py'), astrac, meson.current_build_dir() / 'c-owners'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-com-policies', ints_python,
	args: [files('com-policies.py'), astrac, meson.current_build_dir() / 'com-policies'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-gobject-export', ints_python,
	args: [files('gobject-export/build.py'), '--compiler', astrac, '--output', meson.current_build_dir() / 'gobject-export'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-gobject-import', ints_python,
	args: [files('../ecosystem-abi-8/gir-check.py'), astrac, meson.current_build_dir() / 'gobject-import', 'policy-attributes'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-gobject-import-source', ints_python,
	args: [files('c-pointers.py'), astrac, meson.current_build_dir() / 'gobject-import-source', 'GObjectImport'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-c-unions', ints_python,
	args: [files('c-unions.py'), astrac, meson.current_build_dir() / 'c-unions'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-c-headers', ints_python,
	args: [files('c-headers.py'), astrac, meson.current_build_dir() / 'c-headers'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-a121', ints_python,
	args: [files('applications.py'), astrac, meson.current_build_dir() / 'applications'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-debug-records', ints_python,
	args: [files('debug-records.py'), astrac, meson.current_build_dir() / 'debug-records'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-c-bools', ints_python,
	args: [files('c-bools.py'), astrac, meson.current_build_dir() / 'c-bools'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-a122', ints_python,
	args: [files('a122-binary-parser.py'), astrac, meson.current_build_dir() / 'a122'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-gobject-applications', ints_python,
	args: [files('gobject-applications.py'), astrac, meson.current_build_dir() / 'gobject-applications'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-a129', ints_python,
	args: [files('a129-packaged-transformer.py'), astrac, meson.current_build_dir() / 'a129'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-a131', ints_python,
	args: [files('a131-debugger.py'), astrac, meson.current_build_dir() / 'a131'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('interop-tooling-14-a132-development', ints_python,
	args: [files('a132-installed-system.py'), astrac, meson.current_build_dir() / 'a132'],
	depends: astrac, timeout: 600, workdir: meson.project_source_root())
