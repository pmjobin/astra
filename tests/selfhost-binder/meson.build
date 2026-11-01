# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
binder_runtime = get_option('qualification_runtime')
if binder_runtime == ''
	binder_runtime = meson.current_build_dir() / 'receipts'
endif
binder_args = [files('run.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', binder_runtime / 'binder-component']
test('selfhost-binder', ints_python, args: binder_args, depends: astrac, timeout: 1200, workdir: meson.project_source_root())
run_target('binder-component-check', command: [ints_python] + binder_args, depends: astrac)
