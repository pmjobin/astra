# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
semadmit_runtime = get_option('qualification_runtime')
if semadmit_runtime == ''
	semadmit_runtime = meson.current_build_dir() / 'receipts'
endif
semadmit_args = [files('qualify.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', semadmit_runtime / 'semadmit-component']
test('selfhost-semadmit', ints_python, args: semadmit_args, depends: astrac, timeout: 3000, workdir: meson.project_source_root())
run_target('semadmit-component-check', command: [ints_python] + semadmit_args, depends: astrac)
