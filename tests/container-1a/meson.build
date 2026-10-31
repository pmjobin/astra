# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
slots_contracts = executable('astra-owner-slots-contracts', ['contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('container-1a-contracts', slots_contracts, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root(), timeout: 120)
test('container-1a-native-execution', ints_python, args: [files('execute.py'), astrac, args_llvm, meson.current_build_dir() / 'execution'], depends: [astrac, args_llvm], workdir: meson.project_source_root(), timeout: 240)
test('container-1a-source-refusals', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, workdir: meson.project_source_root(), timeout: 180)
