# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
install_data('text/utf8-message.astra', install_dir: get_option('datadir') / 'astra/text')
install_data('../../examples/utf8-message/main.astra', install_dir: get_option('datadir') / 'astra/examples/utf8-message')
install_data('../../examples/owning-enums/types.astra', '../../examples/owning-enums/produce.astra', '../../examples/owning-enums/consume.astra', '../../examples/owning-enums/main.astra', '../../examples/owning-enums/README.md', install_dir: get_option('datadir') / 'astra/examples/owning-enums')
install_data('../../examples/enums/types.astra', '../../examples/enums/validate.astra', '../../examples/enums/policy.astra', '../../examples/enums/main.astra', '../../examples/enums/README.md', install_dir: get_option('datadir') / 'astra/examples/enums')
install_data('base/order.astra', 'base/classify.astra', 'base/contracts.astra', 'base/clamp.astra', 'base/slices.astra', 'base/buffers.astra', 'base/outcomes.astra', 'base/errors.astra', install_dir: get_option('datadir') / 'astra/base')
install_data('base/diagnostics.astra', install_dir: get_option('datadir') / 'astra/base')
install_data('../runtime/interop/retained.c', '../runtime/interop/retained.h', install_dir: get_option('datadir') / 'astra/interop')
install_data('../runtime/interop/foreign-14.c', '../runtime/interop/foreign-14.h', install_dir: get_option('datadir') / 'astra/interop')
install_data('../runtime/interop/gobject-signals-16.c', '../runtime/interop/gobject-signals-16.h', install_dir: get_option('datadir') / 'astra/interop')
install_data('async/virtual.astra', '../runtime/async/virtual.c', '../runtime/async/virtual.h', '../runtime/async/provider.h', install_dir: get_option('datadir') / 'astra/async')
install_data('async/linux.astra', '../runtime/async/linux.c', '../runtime/async/linux.h', 'async/payload.astra', '../bindings/async/payload.vapi', install_dir: get_option('datadir') / 'astra/async')
install_data('../../docs/platform/linux-uring-timers.md', install_dir: get_option('datadir') / 'astra/docs/platform')
install_data('async/threaded.astra', '../runtime/async/threaded.c', install_dir: get_option('datadir') / 'astra/async')
install_data('../bindings/async/composition.vapi', install_dir: get_option('datadir') / 'astra/async')
install_data('../runtime/async/task-core17.c', '../runtime/async/task-api17.c', '../runtime/async/worker17.c', '../runtime/async/composed.c', install_dir: get_option('datadir') / 'astra/async')
install_data('../runtime/runtime/threads-13.c', '../runtime/runtime/threads-13.h', '../runtime/runtime/monitors-13.c', '../runtime/runtime/monitors-13.h', '../runtime/runtime/singletons-13.c', '../runtime/runtime/actors-13.c', '../runtime/runtime/actors-13.h', install_dir: get_option('datadir') / 'astra/runtime')
install_data('hosted/network.astra', install_dir: get_option('datadir') / 'astra/hosted')
install_data('../runtime/platform/network-posix.c', '../runtime/platform/network-posix.h', install_dir: get_option('datadir') / 'astra/platform')
install_data('../runtime/platform/diagnostics.h', '../runtime/platform/diagnostics-trap.c', '../runtime/platform/diagnostics-hosted.c', install_dir: get_option('datadir') / 'astra/platform')
install_data('hosted/equality.astra', '../bindings/hosted/math.vapi', 'hosted/text.astra', install_dir: get_option('datadir') / 'astra/hosted')
install_data('../runtime/platform/args-posix.h', '../runtime/platform/args-posix.c', install_dir: get_option('datadir') / 'astra/platform')
install_data('../runtime/platform/text-posix.h', '../runtime/platform/text-posix.c', install_dir: get_option('datadir') / 'astra/platform')
install_data('../runtime/platform/failure.h', '../runtime/platform/failure-trap.c', '../runtime/platform/failure-hosted.c', install_dir: get_option('datadir') / 'astra/platform')
install_data('../../examples/allocation-failure/types.astra', '../../examples/allocation-failure/actions.astra', '../../examples/allocation-failure/factory.astra', '../../examples/allocation-failure/main.astra', '../../examples/allocation-failure/application.vapi', '../../examples/allocation-failure/application.c', '../../examples/allocation-failure/README.md', install_dir: get_option('datadir') / 'astra/examples/allocation-failure')

# Support objects have a concrete target identity; they are never autolinked.
if get_option('hosted_concurrency') and (host_machine.system() != 'linux' or host_machine.cpu_family() != 'x86_64' or meson.get_compiler('c').get_id() != 'gcc')
	error('Surge 13 hosted concurrency support objects require GNU Linux x86-64')
endif
if get_option('hosted_concurrency')
	concurrent_support_dir = get_option('libdir') / 'astra/x86_64-linux'
	foreach provider : ['threads-13', 'monitors-13', 'singletons-13', 'actors-13']
		custom_target('astra-' + provider, input: '../runtime/runtime/' + provider + '.c', output: provider + '.o', depend_files: ['../runtime/runtime/threads-13.h', '../runtime/runtime/monitors-13.h', '../runtime/runtime/actors-13.h'], command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: concurrent_support_dir)
	endforeach
	custom_target('astra-async-threaded', input: '../runtime/async/threaded.c', output: 'async-threaded.o', depend_files: ['../runtime/async/task-core17.c', '../runtime/async/task-api17.c', '../runtime/async/worker17.c', '../runtime/async/virtual.h', '../runtime/async/provider.h'], command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: concurrent_support_dir)
	custom_target('astra-async-composed', input: '../runtime/async/composed.c', output: 'async-composed.o', depend_files: ['../runtime/async/task-core17.c', '../runtime/async/task-api17.c', '../runtime/async/worker17.c', '../runtime/async/virtual.h', '../runtime/async/provider.h'], command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: concurrent_support_dir)
	custom_target('astra-network-posix', input: '../runtime/platform/network-posix.c', output: 'network-posix.o', depend_files: '../runtime/platform/network-posix.h', command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: concurrent_support_dir)
	custom_target('astra-context-17', input: '../runtime/runtime/context-17.c', output: 'context-17.o', depend_files: ['../runtime/runtime/context-17.h', '../runtime/async/virtual.h'], command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-pedantic', '-pthread', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: concurrent_support_dir)
endif
if get_option('linux_async') and (host_machine.system() != 'linux' or host_machine.cpu_family() != 'x86_64' or meson.get_compiler('c').get_id() != 'gcc')
	error('L1 Linux async requires the existing GNU LP64 x86-64 Linux/GCC support-object build')
endif
if host_machine.system() == 'linux' and host_machine.cpu_family() == 'x86_64' and meson.get_compiler('c').get_id() == 'gcc'
	base_target = 'x86_64-linux'
	base_support_dir = get_option('libdir') / 'astra' / base_target
	base_providers = []
	retained_provider = custom_target('astra-retained', input: '../runtime/interop/retained.c', output: 'retained.o', depend_files: '../runtime/interop/retained.h', command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: base_support_dir)
	async_provider = custom_target('astra-async-virtual', input: '../runtime/async/virtual.c', output: 'async-virtual.o', depend_files: ['../runtime/async/task-core17.c', '../runtime/async/task-api17.c', '../runtime/async/virtual.h', '../runtime/async/provider.h'], command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: base_support_dir)
	if get_option('linux_async')
		uring_dependency = dependency('liburing', version: '>=2.15', static: true, required: true)
		async_linux_provider = static_library('astra-async-linux', '../runtime/async/linux.c', dependencies: uring_dependency, c_args: ['-O2', '-Wall', '-Wextra', '-Werror'], install: true, install_dir: base_support_dir)
	endif
	text_provider = custom_target('astra-text-posix', input: '../runtime/platform/text-posix.c', output: 'text-posix.o', depend_files: '../runtime/platform/text-posix.h', command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: base_support_dir)
	float_text_provider = custom_target('astra-float-text-posix', input: '../runtime/platform/float-text-posix.c', output: 'float-text-posix.o', depend_files: '../runtime/platform/float-text-posix.h', command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-fast-math', '-ffp-contract=off', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: base_support_dir)
	args_provider = custom_target('astra-args-posix', input: '../runtime/platform/args-posix.c', output: 'args-posix.o', depend_files: '../runtime/platform/args-posix.h', command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: base_support_dir)
	foreach provider : ['trap', 'hosted']
		base_providers += custom_target('astra-base-failure-' + provider, input: '../runtime/platform/failure-' + provider + '.c', output: 'failure-' + provider + '.o', depend_files: '../runtime/platform/failure.h', command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector', '-ffreestanding', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: base_support_dir)
	endforeach
	base_identity = configuration_data()
	diagnostic_providers = []
	foreach provider : ['trap', 'hosted']
		diagnostic_providers += custom_target('astra-diagnostics-' + provider, input: '../runtime/platform/diagnostics-' + provider + '.c', output: 'diagnostics-' + provider + '.o', depend_files: '../runtime/platform/diagnostics.h', command: meson.get_compiler('c').cmd_array() + ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-stack-protector', '-ffreestanding', '-c', '@INPUT@', '-o', '@OUTPUT@'], build_by_default: true, install: true, install_dir: base_support_dir)
	endforeach
	base_identity.set('TARGET', base_target)
	base_identity.set('COMPILER', meson.get_compiler('c').get_id() + ' ' + meson.get_compiler('c').version())
	configure_file(input: 'platform/target.txt.in', output: 'target.txt', configuration: base_identity, install: true, install_dir: base_support_dir)
endif

install_data('memory/byte-arena.astra', install_dir: get_option('datadir') / 'astra/memory')
install_data('../bindings/memory/contexts.vapi', 'memory/contexts.astra', install_dir: get_option('datadir') / 'astra/memory')
install_data('memory/packet-arena.astra', '../bindings/memory/packet-resource.vapi', install_dir: get_option('datadir') / 'astra/memory')
install_data('collections/bag.astra', 'collections/vector.astra',
	'collections/box.astra', 'collections/map.astra', 'collections/cache.astra', install_dir: get_option('datadir') / 'astra/collections')
install_data('collections/context-bag.astra', 'collections/context-map.astra',
	'collections/context-cache.astra', install_dir: get_option('datadir') / 'astra/collections')
install_data('hosted/files.astra', 'hosted/text-ops.astra', install_dir: get_option('datadir') / 'astra/hosted')
install_data('text/scalar-format.astra', 'text/unicode-scalars.astra', 'text/utf8-byte-builder.astra', install_dir: get_option('datadir') / 'astra/text')
install_data('../runtime/platform/files-posix.c', '../runtime/platform/files-posix.h', '../runtime/platform/text-ops-posix.c', 'platform/pc-devices.astra', install_dir: get_option('datadir') / 'astra/platform')
install_data('../runtime/runtime/allocation-12-host.c', '../runtime/runtime/allocation-12.c', '../runtime/runtime/allocation-12.h', install_dir: get_option('datadir') / 'astra/runtime')
install_data('../runtime/runtime/context-17.c', '../runtime/runtime/context-17.h', install_dir: get_option('datadir') / 'astra/runtime')
install_data('../runtime/interop/gobject-signals.c', '../runtime/interop/gobject-signals.h', '../runtime/interop/gobject.c', '../runtime/interop/gobject.h', install_dir: get_option('datadir') / 'astra/interop')
install_data('text/float-format.astra', install_dir: get_option('datadir') / 'astra/text')
install_data('../runtime/platform/float-text-posix.c', '../runtime/platform/float-text-posix.h', install_dir: get_option('datadir') / 'astra/platform')

install_data('numerics/vectors.astra', 'numerics/complex.astra', 'numerics/filters.astra', 'numerics/fir.astra', 'numerics/pcm.astra',
	install_dir: get_option('datadir') / 'astra/numerics')
