# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
enum_firewall_targets = {}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-enum-' + stage, [stage + '-standalone.vala', 'shape.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('enum-' + stage, target, args: ['--tap'], protocol: 'tap')
	enum_firewall_targets += {'enum-' + stage: target}
endforeach
enum_native = executable('astra-enum-native', ['native-standalone.vala', nabi_model_sources, nabi_provenance_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('enum-native', enum_native, args: ['--tap'], protocol: 'tap')
enum_llvm = executable('astra-enum-llvm', ['llvm.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('enum-llvm', enum_llvm, args: ['--tap'], protocol: 'tap')
test('enum-1-source', ints_python, args: [files('source.py'), astrac, meson.current_build_dir() / 'source'], depends: astrac, timeout: 600, workdir: meson.project_source_root())
test('enum-1-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 1200, workdir: meson.project_source_root())
test('enum-1-client', ints_python, args: [files('client.py'), meson.project_build_root(), meson.current_build_dir() / 'client'], depends: astrac, timeout: 1800, workdir: meson.project_source_root(), is_parallel: false)
test('enum-1-cost', ints_python, args: [files('cost.py'), astrac, meson.current_build_dir() / 'cost'], depends: astrac, timeout: 600, workdir: meson.project_source_root())
