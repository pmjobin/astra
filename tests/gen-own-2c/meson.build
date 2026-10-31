# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
gen_result_contracts = executable('astra-gen-result-contracts', 'contracts.vala', dependencies: [core_dependency, nabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-own-2c-contracts', gen_result_contracts, args: ['--tap'], protocol: 'tap')
test('gen-own-2c-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
test('gen-own-2c-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('gen-own-2c-no-llvm', find_program('sh'), args: [meson.project_source_root() / 'tests/frontend/check-linkage.sh', find_program('ldd'), find_program('nm'), gen_result_contracts, find_program('readelf')])
