# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
callable_value_proof = executable('astra-callable-value-proof', ['callable-proof.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-runtime-4-callable-proof', callable_value_proof, args: ['--tap'], protocol: 'tap')
test('language-runtime-4-callable', ints_python, args: [files('callable-check.py'), astrac, meson.current_build_dir() / 'callable'], depends: astrac, timeout: 600, workdir: meson.project_source_root())

closure_value_proof = executable('astra-closure-value-proof', ['closure-proof.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('language-runtime-4-closure-proof', closure_value_proof, args: ['--tap'], protocol: 'tap')
test('language-runtime-4-closure', ints_python, args: [files('closure-check.py'), astrac, meson.current_build_dir() / 'closure'], depends: astrac, timeout: 900, workdir: meson.project_source_root())
test('language-runtime-4-events', ints_python, args: [files('event-check.py'), astrac, meson.current_build_dir() / 'events'], depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('language-runtime-4-report', ints_python, args: [files('report-check.py'), astrac, meson.current_build_dir() / 'report'], depends: astrac, timeout: 600, workdir: meson.project_source_root())
