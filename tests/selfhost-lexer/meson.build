# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
lexer_runtime = get_option('qualification_runtime')
if lexer_runtime == ''
	lexer_runtime = meson.current_build_dir() / 'receipts'
endif
lexer_args = [files('run.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', lexer_runtime / 'lexer-component']
test('selfhost-lexer', ints_python, args: lexer_args, depends: astrac, timeout: 300, workdir: meson.project_source_root())
run_target('lexer-component-check', command: [ints_python] + lexer_args, depends: astrac)
