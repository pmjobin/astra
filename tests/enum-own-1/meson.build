# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
enum_own_firewall_targets = {}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-enum-own-' + stage, [stage + '-standalone.vala', 'shape.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('enum-own-' + stage, target, args: ['--tap'], protocol: 'tap')
	enum_own_firewall_targets += {'enum-own-' + stage: target}
endforeach
enum_own_native = executable('astra-enum-own-native', ['native-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
enum_own_firewall_targets += {'enum-own-native': enum_own_native}
test('enum-own-native', enum_own_native, args: ['--tap'], protocol: 'tap')
test('enum-own-source', ints_python, args: [files('source.py'), astrac, meson.current_build_dir() / 'source'], depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('enum-own-client', ints_python, args: [files('client.py'), meson.project_build_root(), meson.current_build_dir() / 'client'], depends: astrac, timeout: 1200, workdir: meson.project_source_root(), is_parallel: false)
enum_own_llvm = executable('astra-enum-own-llvm', ['llvm.vala', 'verification.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('enum-own-llvm', enum_own_llvm, args: ['--tap'], protocol: 'tap')
test('enum-own-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 1200, workdir: meson.project_source_root(), is_parallel: false)
enum_own_valgrind = find_program('valgrind', required: true)
test('enum-own-memory', ints_python, args: [files('memory.py'), meson.project_build_root(), meson.current_build_dir() / 'memory'], depends: [astrac, enum_own_llvm], timeout: 1200, workdir: meson.project_source_root(), is_parallel: false)
