# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
parser_runtime = get_option('qualification_runtime')
if parser_runtime == ''
	parser_runtime = meson.current_build_dir() / 'receipts'
endif
parser_args = [files('run.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', parser_runtime / 'parser-component']
test('selfhost-parser', ints_python, args: parser_args, depends: astrac, timeout: 1200, workdir: meson.project_source_root())
run_target('parser-component-check', command: [ints_python] + parser_args, depends: astrac)
