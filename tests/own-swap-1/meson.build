# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
own_swap_firewall_targets = {}
foreach stage, sources : {'core': core_model_sources, 'cfg': cfg_model_sources, 'ssa': ssa_model_sources}
	target = executable('astra-own-swap-' + stage, [stage + '-standalone.vala', sources, ir_authority_sources], dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args)
	test('own-swap-' + stage, target, args: ['--tap'], protocol: 'tap')
	own_swap_firewall_targets += {'own-swap-' + stage: target}
endforeach
own_swap_llvm = executable('astra-own-swap-llvm', ['support.vala', 'llvm.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'], dependencies: llvm_backend_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args)
test('own-swap-llvm', own_swap_llvm, args: ['--tap'], protocol: 'tap', workdir: meson.project_source_root())
test('own-swap-source', ints_python, args: [files('source.py'), astrac, meson.current_build_dir() / 'source'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
test('own-swap-execution', ints_python, args: [files('execute.py'), astrac, meson.current_build_dir() / 'execution'], depends: astrac, timeout: 1200, workdir: meson.project_source_root())
test('own-swap-equivalence', ints_python, args: [files('equivalence.py'), astrac, meson.current_build_dir() / 'equivalence'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
test('own-swap-effects', ints_python, args: [files('effects.py'), astrac, meson.current_build_dir() / 'effects'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
test('own-swap-installed-client', ints_python, args: [files('client.py'), meson.project_build_root(), meson.current_build_dir() / 'client'], depends: [astrac, args_provider] + diagnostic_providers, is_parallel: false, timeout: 600, workdir: meson.project_source_root())
test('own-swap-cad-rotation', ints_python, args: [files('cad.py'), astrac, meson.current_build_dir() / 'cad'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
