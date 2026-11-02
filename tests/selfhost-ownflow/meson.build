# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
ownflow_runtime = get_option('qualification_runtime')
if ownflow_runtime == ''
	ownflow_runtime = meson.current_build_dir() / 'receipts'
endif
ownflow_args = [files('run.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', ownflow_runtime / 'ownflow-component']
test('selfhost-ownflow', ints_python, args: ownflow_args, depends: astrac, timeout: 2400, workdir: meson.project_source_root())
run_target('ownflow-component-check', command: [ints_python] + ownflow_args, depends: astrac)
