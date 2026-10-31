# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
builder_contracts = executable('astra-byte-builder-contracts', ['contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('text-own-1b-contracts', builder_contracts, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root(), timeout: 120)
test('text-own-1b-native-execution', ints_python, args: [files('execute.py'), astrac, args_llvm, meson.current_build_dir() / 'execution'], depends: [astrac, args_llvm], workdir: meson.project_source_root(), timeout: 300)
test('text-own-1b-source-refusals', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, workdir: meson.project_source_root(), timeout: 120)
