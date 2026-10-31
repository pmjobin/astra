# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
struct_move_contracts = executable('astra-struct-move-contracts', 'contracts.vala', dependencies: ssa_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('struct-move-1-stage-contracts', struct_move_contracts, args: ['--tap'], protocol: 'tap')
test('struct-move-1-native-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
