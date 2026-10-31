# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
systems_optimizer = executable('astra-public-optimizer-contracts', 'optimizer.vala', dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('compiler-systems-2-optimizer-contracts', systems_optimizer, args: ['--tap'], protocol: 'tap', timeout: 120)
systems_runtime = meson.project_build_root() / '..' / 'runtime'
test('compiler-systems-2-applications', ints_python,
	args: [files('execute.py'), astrac, args_llvm, meson.current_build_dir() / 'execution', systems_runtime],
	depends: [astrac, args_llvm], workdir: meson.project_source_root(), timeout: 600)
test('compiler-systems-2-predecessor-public-O2', ints_python,
	args: [files('public-corpus.py'), astrac, args_llvm, meson.current_build_dir() / 'predecessor'],
	depends: [astrac, args_llvm], workdir: meson.project_source_root(), timeout: 600)
