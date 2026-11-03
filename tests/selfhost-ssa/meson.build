# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
ssa_runtime = get_option('qualification_runtime')
if ssa_runtime == ''
	ssa_runtime = meson.current_build_dir() / 'receipts'
endif
ssa_args = [files('qualify.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', ssa_runtime / 'ssa-component']
test('selfhost-ssa', ints_python, args: ssa_args, depends: astrac, timeout: 7200, workdir: meson.project_source_root())
run_target('ssa-component-check', command: [ints_python] + ssa_args, depends: astrac)
