# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
utf8_contracts = executable('astra-utf8-message-contracts', ['contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('text-own-1a-contracts', utf8_contracts, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root(), timeout: 90)
test('text-own-1a-native-execution', ints_python, args: [files('execute.py'), astrac, args_llvm, meson.current_build_dir() / 'execution'], depends: [astrac, args_llvm], workdir: meson.project_source_root(), timeout: 240)
