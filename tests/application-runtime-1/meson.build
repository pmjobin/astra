# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
application_contracts = executable('astra-application-contracts', ['contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('application-runtime-1-contracts', application_contracts, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root(), timeout: 120)
test('application-runtime-1-execution', ints_python, args: [files('execute.py'), astrac, args_llvm, meson.current_build_dir() / 'execution'], depends: [astrac, args_llvm], workdir: meson.project_source_root(), timeout: 600)
