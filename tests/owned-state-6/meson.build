# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
owned_state_proof = executable('astra-owned-state-proof', ['contracts.vala', 'record-contracts.vala', 'lazy-contracts.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: [llvm_backend_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('owned-state-6-proof', owned_state_proof, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root(), timeout: 180)
test('owned-state-6-runtime', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'runtime'], depends: astrac, workdir: meson.project_source_root(), timeout: 480)
test('owned-state-6-refusals', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, workdir: meson.project_source_root(), timeout: 240)
test('owned-state-6-sanitizers', ints_python, args: [files('memory.py'), astrac, args_llvm, meson.current_build_dir() / 'sanitizers'], depends: [astrac, args_llvm], workdir: meson.project_source_root(), timeout: 240, env: ['PYTHONDONTWRITEBYTECODE=1'])
