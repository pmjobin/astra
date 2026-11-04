# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

# Meson's LLVM dependency requires C++; this project uses only the C API.
llvm_config = find_program('llvm-config')
llvm_version = run_command(llvm_config, '--version', check: true).stdout().strip()
if llvm_version.split('.')[0] != '23'
	error('ASTRA-EXEC-1 requires system LLVM major 23; llvm-config reports ' + llvm_version)
endif

llvm_cflags = run_command(llvm_config, '--cflags', check: true).stdout().strip().split()
llvm_ldflags = run_command(llvm_config, '--link-shared', '--ldflags', '--libs', '--system-libs', 'core', 'analysis', 'native', check: true).stdout().strip().split()
llvm_dependency = declare_dependency(compile_args: llvm_cflags, link_args: llvm_ldflags)

if not meson.get_compiler('c').links(files('capi/check.c'), dependencies: llvm_dependency, name: 'LLVM 23 C API headers and linkage')
	error('The selected system LLVM must provide matching LLVM 23 headers and the required Core/Analysis/Target/TargetMachine C API. See meson-logs/meson-log.txt.')
endif

llvm_smoke_sources = files('smoke.vala', 'capi/llvm.vapi')
llvm_backend_sources = files('llvm-arguments.vala', 'llvm-text.vala', 'llvm-module.vala', 'llvm-type-mapper.vala', 'llvm-c-type-mapper.vala', 'llvm-c-import.vala', 'llvm-c-export.vala', 'llvm-lowering.vala', 'llvm-function-lowering.vala', 'llvm-buffer-allocation.vala', 'llvm-buffer-exchange.vala', 'llvm-struct-storage.vala', 'llvm-sum-values.vala', 'llvm-scalar-lowering.vala', 'llvm-target-machine.vala', 'capi/llvm.vapi', 'capi/llvm-target.vapi')
llvm_backend_sources += files('llvm-continuations.vala', 'llvm-owner-slots.vala', 'llvm-shared.vala', 'llvm-closures.vala', 'llvm-retained.vala', 'llvm-callbacks.vala')
llvm_backend_sources += files('llvm-classes.vala')
llvm_backend_sources += files('llvm-async-frames.vala')
llvm_backend_sources += files('llvm-lazy-properties.vala')
llvm_backend_sources += files('llvm-debug.vala', 'capi/llvm-debug.vapi')
llvm_backend_sources += files('llvm-native-modules.vala')
llvm_backend_sources += files('llvm-runtime-profile.vala')
llvm_backend_sources += files('llvm-volatile.vala')
llvm_backend_sources += files('llvm-numeric-contract.vala', 'llvm-vector-memory.vala')
llvm_backend_sources += files('llvm-effects.vala')
llvm_backend_sources += files('llvm-pc-devices.vala')
llvm_backend_sources += files('llvm-allocation-policy.vala')
llvm_backend_sources += files('llvm-runtime-lifetimes.vala')
llvm_backend_sources += files('llvm-constructor-stack.vala')
llvm_backend_sources += files('llvm-context-inputs.vala')
llvm_backend_sources += files('capi/native-proof.c')
llvm_backend_sources += files('llvm-owned-inputs.vala')
llvm_backend_sources += files('llvm-heap-carriers.vala')
llvm_backend_sources += files('llvm-shared-atomics.vala')
llvm_backend_sources += files('llvm-concurrency.vala')
llvm_backend_sources += files('llvm-foreign-classes.vala')
llvm_backend_sources += files('llvm-foreign-imports.vala')
llvm_backend_dependency = declare_dependency(sources: llvm_backend_sources, include_directories: include_directories('capi'), dependencies: [nabi_dependency, cabi_dependency, llvm_dependency])
