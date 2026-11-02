# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
flowsem_runtime = get_option('qualification_runtime')
if flowsem_runtime == ''
	flowsem_runtime = meson.current_build_dir() / 'receipts'
endif
flowsem_args = [files('qualify.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', flowsem_runtime / 'flowsem-component']
test('selfhost-flowsem', ints_python, args: flowsem_args, depends: astrac, timeout: 2400, workdir: meson.project_source_root())
run_target('flowsem-component-check', command: [ints_python] + flowsem_args, depends: astrac)
