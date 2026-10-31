# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
cabi_buffer_standalone = executable('astra-cabi-buffer-standalone', ['standalone.vala', cabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('cabi-buffer-standalone', cabi_buffer_standalone, args: ['--tap'], protocol: 'tap')
cabi_buffer_pipeline = executable('astra-cabi-buffer-pipeline', ['pipeline.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('cabi-buffer-pipeline', cabi_buffer_pipeline, args: ['--tap'], protocol: 'tap')
cabi_buffer_provider = executable('astra-cabi-buffer-provider', ['provider.c', '../../lib/runtime/platform/files-posix.c'])
test('cabi-buffer-provider', cabi_buffer_provider)
test('cabi-buffer-qualification', ints_python, args: [files('qualify.py'), astrac, meson.current_build_dir() / 'qualification'], depends: [astrac], workdir: meson.project_source_root(), timeout: 180)
