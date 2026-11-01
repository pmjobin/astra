# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
source_component_runtime = get_option('qualification_runtime')
if source_component_runtime == ''
	source_component_runtime = meson.current_build_dir() / 'receipts'
endif
source_component_args = [files('run.py'), '--compiler', astrac, '--build', meson.current_build_dir() / 'products', '--runtime', source_component_runtime / 'source-component']
test('selfhost-foundation-source', ints_python, args: source_component_args, depends: astrac, timeout: 300, workdir: meson.project_source_root())
run_target('source-component-check', command: [ints_python] + source_component_args, depends: astrac)
