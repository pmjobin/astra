# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
test('app-diag-collection-0', ints_python, args: [files('execute.py'), astrac, args_llvm, meson.current_build_dir() / 'execution'], depends: [astrac, args_llvm], timeout: 180, workdir: meson.project_source_root())
