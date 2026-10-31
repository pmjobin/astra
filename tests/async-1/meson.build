# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
async_parser = executable('astra-async-parser', 'parse-tests.vala', dependencies: frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('async-1-parser', async_parser, args: ['--tap'], protocol: 'tap')
async_runtime_tests = executable('astra-async-runtime', ['runtime-tests.c', '../../lib/runtime/async/virtual.c'], include_directories: include_directories('../../lib/astra/async'), c_args: ['-DASTRA_ASYNC_TEST_PROTOCOL'])
test('async-1-runtime-protocol', async_runtime_tests)
async_frame_tests = executable('astra-async-frames', ['frame-tests.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: [llvm_backend_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('async-1-native-frames', async_frame_tests, args: ['--tap'], protocol: 'tap')
test('async-1-source-frame-execution', ints_python, args: [files('execute-frames.py'), async_frame_tests, meson.current_build_dir() / 'source-frames'], depends: async_frame_tests, timeout: 300, workdir: meson.project_source_root())
if host_machine.system() == 'linux' and host_machine.cpu_family() == 'x86_64' and meson.get_compiler('c').get_id() == 'gcc'
	test('async-1-installed-source-orders', ints_python, args: [files('install.py'), meson.project_build_root(), meson.current_build_dir() / 'installed'], depends: [astrac, async_provider], timeout: 300, workdir: meson.project_source_root())
endif
