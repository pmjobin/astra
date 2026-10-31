# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# Independent frontend: no Astra syntax, semantics, IR, ABI, or LLVM sources.
vapi_frontend_tests = executable('astra-vapi-frontend-tests', 'frontend.vala', dependencies: vapi_frontend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vapi-frontend', vapi_frontend_tests, args: ['--tap'], protocol: 'tap')

vapi_tests = executable('astra-vapi-tests', ['support.vala', 'pipeline.vala', 'metadata.vala'], dependencies: [vapi_dependency, cabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vapi', vapi_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())

vapi_test_alias_sources = files('aliases.vala')
vapi_llvm_tests = executable('astra-vapi-llvm-tests', ['support.vala', vapi_test_alias_sources, 'llvm.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: [vapi_dependency, llvm_backend_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('vapi-llvm', vapi_llvm_tests, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())

# Test-only physical implementations; headers in VAPI never trigger this build.
vapi_companion = custom_target('vapi-companion', input: 'companion.c', output: 'companion.o', build_by_default: true, command: [meson.get_compiler('c').cmd_array(), '-std=c11', '-Wall', '-Wextra', '-Werror', '-c', '@INPUT@', '-o', '@OUTPUT@'])
