# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
gen_borrow_contracts = executable('astra-gen-borrow-contracts', 'contracts.vala', dependencies: [core_dependency, nabi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args)
test('gen-borrow-1-contracts', gen_borrow_contracts, args: ['--tap'], protocol: 'tap')
test('gen-borrow-1-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('gen-borrow-1-negative', ints_python, args: [files('negative.py'), astrac, meson.current_build_dir() / 'negative'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('gen-borrow-1-no-llvm', find_program('sh'), args: [meson.project_source_root() / 'tests/frontend/check-linkage.sh', find_program('ldd'), find_program('nm'), gen_borrow_contracts, find_program('readelf')])
