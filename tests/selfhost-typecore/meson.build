# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
typecore_runtime = get_option('qualification_runtime')
if typecore_runtime == ''
	typecore_runtime = meson.current_build_dir() / 'receipts'
endif
typecore_args = [files('run.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', typecore_runtime / 'typecore-component']
test('selfhost-typecore', ints_python, args: typecore_args, depends: astrac, timeout: 1800, workdir: meson.project_source_root())
run_target('typecore-component-check', command: [ints_python] + typecore_args, depends: astrac)
