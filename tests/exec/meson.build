# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

failing_linker = executable('astra-failing-linker', 'failing-linker.vala', dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
exec_tests = executable('astra-exec-tests', ['support.vala', 'runtime.vala', 'matrix.vala', 'backend.vala', 'driver.vala', 'loops.vala', 'loop-control.vala', 'shortcircuit.vala', 'c-imports.vala', 'c-exports.vala', 'vapi.vala', 'vapi-metadata.vala', 'pointers.vala', 'structs.vala', 'typed-pointers.vala', 'borrows.vala', 'ownership.vala', vapi_test_alias_sources, '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: execution_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
exec_environment = environment({'ASTRA_TEST_PTR_OBJECT': ptr_companion.full_path(), 'ASTRA_TEST_PTR_EXPORT_OBJECT': ptr_export_companion.full_path(), 'ASTRA_TEST_VAPI_OBJECT': vapi_companion.full_path(), 'ASTRA_TEST_COMPILER': astrac.full_path(), 'ASTRA_TEST_LINK_FAILURE': failing_linker.full_path(), 'LC_ALL': 'C', 'ASTRA_TEST_C_OBJECT': cabi_companion.full_path(), 'ASTRA_TEST_C_OBJECT_SECOND': cabi_second.full_path(), 'ASTRA_TEST_RECORD_LINKER': cabi_record_linker.full_path()})
foreach variant : range(1, 8)
	exec_environment.set('ASTRA_TEST_CEXPORT_OBJECT_' + variant.to_string(), cexport_objects[variant - 1].full_path())
endforeach
exec_nm = find_program('nm', required: false)
if exec_nm.found()
	exec_environment.set('ASTRA_TEST_NM', exec_nm.full_path())
endif
exec_readelf = find_program('readelf', required: false)
if exec_readelf.found()
	exec_environment.set('ASTRA_TEST_READELF', exec_readelf.full_path())
endif
test('native-execution', exec_tests, args: ['--tap'], protocol: 'tap', env: exec_environment, depends: [astrac, failing_linker, cabi_companion, cabi_second, cabi_record_linker, vapi_companion, ptr_companion, ptr_export_companion] + cexport_objects, workdir: meson.project_source_root(), timeout: 120)
