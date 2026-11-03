# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
llvm_component_runtime = get_option('qualification_runtime')
if llvm_component_runtime == ''
	llvm_component_runtime = meson.current_build_dir() / 'receipts'
endif
llvm_component_args = [files('qualify.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', llvm_component_runtime / 'llvm-component']
test('selfhost-llvm', ints_python, args: llvm_component_args, depends: astrac, timeout: 7200, workdir: meson.project_source_root())
run_target('llvm-component-check', command: [ints_python] + llvm_component_args, depends: astrac)
