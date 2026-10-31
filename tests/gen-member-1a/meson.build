# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
gen_member_contracts = executable('astra-gen-member-contracts', ['contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-member-1a-contracts', gen_member_contracts, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root(), timeout: 180)
test('gen-member-1a-native-execution', ints_python, args: [files('execute.py'), astrac, args_llvm, meson.current_build_dir() / 'execution'], depends: [astrac, args_llvm], workdir: meson.project_source_root(), timeout: 300)
test('gen-member-1a-source-refusals', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, workdir: meson.project_source_root(), timeout: 180)
