# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
foreign_schema_proof = executable('astra-declaration-foreign-schema-proof',
	['schema.vala', foreign_schema_sources],
	dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('declaration-interop-16-schema', foreign_schema_proof, args: ['--tap'], protocol: 'tap')
test('declaration-interop-16-signals', ints_python,
	args: [files('signals.py'), astrac, meson.current_build_dir() / 'signals'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-empty-parameters', ints_python,
	args: [files('empty-parameters.py'), astrac, meson.current_build_dir() / 'empty-parameters'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-api-a', ints_python,
	args: [files('api-a.py'), astrac, meson.current_build_dir() / 'api-a'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-opaque-channels', ints_python,
	args: [files('opaque-channels.py'), astrac, meson.current_build_dir() / 'opaque-channels'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-opaque-imports', ints_python,
	args: [files('opaque-imports.py'), astrac, meson.current_build_dir() / 'opaque-imports'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-retained-signals-runtime', ints_python,
	args: [files('retained-signals-runtime.py'), meson.current_build_dir() / 'retained-signals-runtime'],
	workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-retained-signals', ints_python,
	args: [files('retained-signals.py'), astrac, meson.current_build_dir() / 'retained-signals'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
foreign_contract_proof = executable('astra-declaration-foreign-contract-proof',
	['contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: [llvm_backend_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('declaration-interop-16-contracts', foreign_contract_proof, args: ['--tap'], protocol: 'tap')
test('declaration-interop-16-scalars', ints_python,
	args: [files('scalars.py'), astrac, meson.current_build_dir() / 'scalars'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-bytes', ints_python,
	args: [files('bytes.py'), astrac, meson.current_build_dir() / 'bytes'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-text', ints_python,
	args: [files('text.py'), astrac, meson.current_build_dir() / 'text'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-records', ints_python,
	args: [files('records.py'), astrac, meson.current_build_dir() / 'records'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-objects', ints_python,
	args: [files('objects.py'), astrac, meson.current_build_dir() / 'objects'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-owners', ints_python,
	args: [files('owners.py'), astrac, meson.current_build_dir() / 'owners'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-errors', ints_python,
	args: [files('errors.py'), astrac, meson.current_build_dir() / 'errors'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-scalar-outs', ints_python,
	args: [files('scalar-outs.py'), astrac, meson.current_build_dir() / 'scalar-outs'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-constructors', ints_python,
	args: [files('constructors.py'), astrac, meson.current_build_dir() / 'constructors'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-imports', ints_python,
	args: [files('imports.py'), astrac, meson.current_build_dir() / 'imports'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-import-references', ints_python,
	args: [files('import-references.py'), astrac, meson.current_build_dir() / 'import-references'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-import-counted', ints_python,
	args: [files('import-counted.py'), astrac, meson.current_build_dir() / 'import-counted'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-import-owned', ints_python,
	args: [files('import-owned.py'), astrac, meson.current_build_dir() / 'import-owned'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-import-records', ints_python,
	args: [files('import-records.py'), astrac, meson.current_build_dir() / 'import-records'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-import-handles', ints_python,
	args: [files('import-handles.py'), astrac, meson.current_build_dir() / 'import-handles'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-import-consuming', ints_python,
	args: [files('import-consuming.py'), astrac, meson.current_build_dir() / 'import-consuming'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-foreign-handles', ints_python,
	args: [files('foreign-handles.py'), astrac, meson.current_build_dir() / 'foreign-handles'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-import-properties', ints_python,
	args: [files('import-properties.py'), astrac, meson.current_build_dir() / 'import-properties'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-native-callables', ints_python,
	args: [files('native-callables.py'), astrac, meson.current_build_dir() / 'native-callables'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-callback-views', ints_python,
	args: [files('callback-views.py'), astrac, meson.current_build_dir() / 'callback-views'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-callbacks', ints_python,
	args: [files('callbacks.py'), astrac, meson.current_build_dir() / 'callbacks'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-import-callbacks', ints_python,
	args: [files('import-callbacks.py'), astrac, meson.current_build_dir() / 'import-callbacks'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
foreign_windows_proof = executable('astra-declaration-windows-proof',
	['windows-contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: execution_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('declaration-interop-16-windows-contracts', foreign_windows_proof, args: ['--tap'], protocol: 'tap')
test('declaration-interop-16-com-import-policies', ints_python,
	args: [files('com-import-policies.py'), astrac, meson.current_build_dir() / 'com-import-policies'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-com-export-policies', ints_python,
	args: [files('com-export-policies.py'), astrac, meson.current_build_dir() / 'com-export-policies'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-gobject-scalars', ints_python,
	args: [files('gobject-scalars.py'), astrac, meson.current_build_dir() / 'gobject-scalars'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-gobject-policies', ints_python,
	args: [files('gobject-policies.py'), astrac, meson.current_build_dir() / 'gobject-policies'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])

test('declaration-interop-16-gobject-imports', ints_python,
	args: [files('gobject-imports.py'), astrac, meson.current_build_dir() / 'gobject-imports'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-gobject-import-policies', ints_python,
	args: [files('gobject-import-policies.py'), astrac, meson.current_build_dir() / 'gobject-import-policies'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-gobject-roundtrip', ints_python,
	args: [files('gobject-roundtrip.py'), astrac, meson.current_build_dir() / 'gobject-roundtrip'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-captured-callbacks', ints_python,
	args: [files('captured-callbacks.py'), astrac, meson.current_build_dir() / 'captured-callbacks'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-personalities', ints_python,
	args: [files('personalities.py'), '--compiler', astrac, '--output', meson.current_build_dir() / 'personalities'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-foreign-units', ints_python,
	args: [files('foreign-units.py'), astrac, meson.current_build_dir() / 'foreign-units'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-gobject-unit', ints_python,
	args: [files('gobject-unit.py'), astrac, meson.current_build_dir() / 'gobject-unit'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
test('declaration-interop-16-com-unit-policies', ints_python,
	args: [files('com-unit-policies.py'), astrac, meson.current_build_dir() / 'com-unit-policies'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])

test('declaration-interop-16-api-b2', ints_python,
	args: [files('api-b2.py'), astrac, meson.current_build_dir() / 'api-b2'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])

test('declaration-interop-16-api-b3', ints_python,
	args: [files('api-b3.py'), astrac, meson.current_build_dir() / 'api-b3'],
	depends: astrac, workdir: meson.project_source_root(), timeout: 180,
	env: ['PYTHONDONTWRITEBYTECODE=1'])
