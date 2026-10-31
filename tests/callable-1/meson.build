# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
callable_native = executable('astra-callable-native', ['native-standalone.vala', nabi_model_sources, nabi_provenance_sources, native_provenance_test_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('callable-native-standalone', callable_native, args: ['--tap'], protocol: 'tap')
callable_tests = executable('astra-callable-tests', ['support.vala', 'qualification.vala', 'review-probes.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('callable-model-and-lifetime', callable_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('callable-generated-native', ints_python, args: [files('execute.py'), callable_tests, meson.current_build_dir() / 'native'], depends: callable_tests, timeout: 300, workdir: meson.project_source_root())
test('callable-native-no-llvm', find_program('sh'), args: [files('../frontend/check-linkage.sh'), find_program('ldd'), find_program('nm'), callable_native, find_program('readelf')])
