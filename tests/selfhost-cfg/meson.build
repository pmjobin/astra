# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
cfg_runtime = get_option('qualification_runtime')
if cfg_runtime == ''
	cfg_runtime = meson.current_build_dir() / 'receipts'
endif
cfg_args = [files('qualify.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', cfg_runtime / 'cfg-component']
test('selfhost-cfg', ints_python, args: cfg_args, depends: astrac, timeout: 3600, workdir: meson.project_source_root())
run_target('cfg-component-check', command: [ints_python] + cfg_args, depends: astrac)
