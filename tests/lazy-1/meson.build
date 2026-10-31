# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
lazy_contracts = executable('astra-lazy-contracts', ['contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('lazy-1-contracts', lazy_contracts, args: ['--tap'], protocol: 'tap')
test('lazy-1-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
test('lazy-1-installed-execution', ints_python, args: [files('install.py'), meson.project_build_root(), meson.current_build_dir() / 'installed'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
