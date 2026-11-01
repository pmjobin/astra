# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
shared_lifetime_proof = executable('astra-shared-lifetime-proof', ['contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('shared-1b-contracts', shared_lifetime_proof, args: ['--tap'], protocol: 'tap')
test('shared-1b-native', ints_python, args: [files('qualify.py'), astrac, meson.current_build_dir() / 'native'], depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('shared-1b-applications', ints_python, args: [files('apps.py'), astrac, meson.current_build_dir() / 'applications'], depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('shared-1b-identity', ints_python, args: [files('identity.py'), astrac, meson.current_build_dir() / 'identity'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
