# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
wide_values = executable('astra-wide-values', ['values.vala', semantic_type_sources, scalar_value_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('wide-values', wide_values, args: ['--tap'], protocol: 'tap')
wide_verifier = executable('astra-wide-verifier', ['verifiers.vala', ssa_model_sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('wide-ssa-verifier', wide_verifier, args: ['--tap'], protocol: 'tap')
wide_llvm = executable('astra-wide-llvm', ['llvm.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('wide-llvm-verifier', wide_llvm, args: ['--tap'], protocol: 'tap')
if scalar_cc.has_multi_arguments(scalar_ubsan_args)
	wide_ubsan = executable('astra-wide-values-ubsan', ['values.vala', semantic_type_sources, scalar_value_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args + scalar_ubsan_args)
	test('wide-values-ubsan', wide_ubsan, args: ['--tap'], protocol: 'tap')
endif
test('wide-public-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
