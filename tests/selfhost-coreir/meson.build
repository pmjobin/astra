# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
coreir_runtime = get_option('qualification_runtime')
if coreir_runtime == ''
	coreir_runtime = meson.current_build_dir() / 'receipts'
endif
coreir_args = [files('qualify.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', coreir_runtime / 'coreir-component']
test('selfhost-coreir', ints_python, args: coreir_args, depends: astrac, timeout: 2400, workdir: meson.project_source_root())
run_target('coreir-component-check', command: [ints_python] + coreir_args, depends: astrac)
