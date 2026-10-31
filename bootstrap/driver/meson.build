# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

if meson.is_cross_build()
	error('ASTRA-EXEC-1 supports only native builds and host-native executable production')
endif

host_linker_argv = meson.get_compiler('c').cmd_array()
# Meson may prepend an automatic C compilation cache. It serves no purpose
# when linking native objects, so configure the actual compiler driver.
if ['ccache', 'sccache'].contains(fs.name(host_linker_argv[0]))
	host_linker_argv = host_linker_argv.slice(1, host_linker_argv.length())
endif
host_linker = find_program(host_linker_argv[0], native: true)
host_linker_argv = [host_linker.full_path()] + host_linker_argv.slice(1, host_linker_argv.length())
host_linker_arguments = []
foreach argument : host_linker_argv
	host_linker_arguments += '"' + argument.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '\\r') + '"'
endforeach
linker_config = configuration_data()
linker_config.set('HOST_LINKER_ARGUMENTS', ', '.join(host_linker_arguments))
linker_config_source = configure_file(input: 'linker-config.vala.in', output: 'linker-config.vala', configuration: linker_config)
host_linker_sources = files('program-entry.vala', 'host-linker.vala')
native_descriptor_sources = files('native-descriptors.vala')
native_descriptor_sources += files('foreign-adapters.vala')
native_descriptor_sources += files('com-adapters.vala')
native_descriptor_sources += files('com-imports.vala')
native_descriptor_sources += files('com-declared.vala')
native_descriptor_sources += files('gobject-adapters.vala')
native_descriptor_sources += files('gobject-declared.vala')
native_descriptor_sources += files('gobject-imports.vala')
execution_sources = host_linker_sources + files('executable-output.vala', 'native-compilation.vala', 'native-module.vala', 'native-optimizer.vala', 'runtime-profile-admission.vala') + native_descriptor_sources
execution_dependency = declare_dependency(sources: execution_sources + [linker_config_source], dependencies: llvm_backend_dependency)
