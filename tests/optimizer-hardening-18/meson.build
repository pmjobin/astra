# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
metadata18_runtime = get_option('qualification_runtime')
if metadata18_runtime == ''
	metadata18_runtime = meson.current_build_dir()
endif
metadata18_runtime = metadata18_runtime / 'optimizer-hardening-18'
test('optimizer-hardening-18-historical-profile-guard', ints_python,
	args: [files('freeze-guard.py'), metadata18_runtime / 'freeze-guard'],
	timeout: 30, workdir: meson.project_source_root())
test('optimizer-hardening-18-registry-contracts', ints_python,
	args: [files('registry-audit.py'), meson.project_build_root(), metadata18_runtime / 'registry-audit'],
	depends: astrac, timeout: 30, workdir: meson.project_source_root())
test('optimizer-hardening-18-metadata-fuzz', ints_python,
	args: [files('metadata-fuzz.py'), astrac, meson.current_build_dir() / 'metadata-fuzz', metadata18_runtime / 'metadata-fuzz'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('optimizer-hardening-18-release-policy', ints_python,
	args: [files('release-policy.py'), meson.current_build_dir() / 'release-policy', metadata18_runtime / 'release-policy'],
	timeout: 30, workdir: meson.project_source_root())
native18_object_checker = executable('astra-native18-object-proof',
	files('native-proof-driver.c', '../../bootstrap/backend/llvm/capi/native-proof.c'),
	include_directories: include_directories('../../bootstrap/backend/llvm/capi'),
	dependencies: llvm_dependency, override_options: ['werror=true'])
test('optimizer-hardening-18-native-object-proof', ints_python,
	args: [files('native-proof.py'), native18_object_checker, meson.current_build_dir() / 'native-object-proof', metadata18_runtime / 'native-object-proof'],
	depends: native18_object_checker, timeout: 120, workdir: meson.project_source_root())
test('optimizer-hardening-18-native-summary', ints_python,
	args: [files('native-summary.py'), astrac, meson.current_build_dir() / 'native-summary', metadata18_runtime / 'native-summary'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('optimizer-hardening-18-native-unknown-cost', ints_python,
	args: [files('native-proof-cost.py'), astrac, meson.current_build_dir() / 'native-proof-cost', metadata18_runtime / 'native-proof-cost'],
	depends: astrac, timeout: 180, is_parallel: false, workdir: meson.project_source_root())
metadata18_decoder = executable('astra-metadata18-decoder',
	files('lifetime-decode.vala') + runtime_lifetime_sources,
	dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args,
	override_options: ['optimization=2', 'werror=true'])
metadata18_tests = executable('astra-metadata18-tests',
	files('lifetime-metadata.vala') + runtime_lifetime_sources,
	dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args,
	override_options: ['optimization=2', 'werror=true'])
test('optimizer-hardening-18-metadata', metadata18_tests, args: ['--tap'],
	protocol: 'tap', timeout: 60, workdir: meson.project_source_root())
test('optimizer-hardening-18-lifetime-framing', ints_python,
	args: [files('lifetime-framing.py'), astrac, metadata18_decoder,
	metadata18_runtime / 'lifetime-framing'],
	depends: [astrac, metadata18_decoder], timeout: 120, workdir: meson.project_source_root())
test('optimizer-hardening-18-lsp-resources', ints_python,
	args: [files('lsp-resources.py'), metadata18_runtime / 'lsp-resources', '--deadlines'],
	timeout: 120, is_parallel: false, workdir: meson.project_source_root())
storage18_tests = executable('astra-storage18-proof', files('storage-contracts.vala'),
	dependencies: [ssa_dependency, vapi_dependency],
	vala_args: frontend_vala_args, c_args: frontend_c_args,
	# Detached SSA excludes driver consumers of three internal methods. Keep
	# those unused-method warnings visible; the production compiler stays strict.
	override_options: ['werror=false'])
test('optimizer-hardening-18-storage-contracts', storage18_tests, args: ['--tap'],
	protocol: 'tap', timeout: 60, workdir: meson.project_source_root())
metadata18_pressure = executable('astra-metadata18-pressure',
	files('lifetime-pressure.vala') + runtime_lifetime_sources,
	dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args,
	override_options: ['optimization=2', 'werror=true'])
test('optimizer-hardening-18-lifetime-pressure', ints_python,
	args: [files('lifetime-pressure.py'), metadata18_pressure, metadata18_runtime / 'pressure'],
	depends: metadata18_pressure, timeout: 180, is_parallel: false, workdir: meson.project_source_root())
test('optimizer-hardening-18-storage-execution', ints_python,
	args: [files('storage.py'), astrac, meson.current_build_dir() / 'storage', metadata18_runtime / 'storage'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('optimizer-hardening-18-view-storage-execution', ints_python,
	args: [files('view-storage.py'), astrac, meson.current_build_dir() / 'view-storage', metadata18_runtime / 'view-storage'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('optimizer-hardening-18-dispatch-execution', ints_python,
	args: [files('dispatch.py'), astrac, meson.current_build_dir() / 'dispatch', metadata18_runtime / 'dispatch'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('optimizer-hardening-18-shared-execution', ints_python,
	args: [files('shared.py'), astrac, meson.current_build_dir() / 'shared', metadata18_runtime / 'shared'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('optimizer-hardening-18-composition-proofs', ints_python,
	args: [files('composition-proofs.py'), astrac, meson.current_build_dir() / 'composition-proofs', metadata18_runtime / 'composition-proofs'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('optimizer-hardening-18-checked-storage-execution', ints_python,
	args: [files('storage.py'), astrac, meson.current_build_dir() / 'checked-storage', metadata18_runtime / 'checked-storage', '--checked'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
application18_profiles = ['sequential']
application18_arguments = []
if get_option('hosted_concurrency')
	application18_profiles += ['threaded']
endif
if get_option('linux_async')
	application18_profiles += ['uring']
	application18_arguments += ['--uring-prefix', uring_prefix]
endif
test('optimizer-hardening-18-application-a', ints_python,
	args: [files('application-a.py'), astrac, meson.current_build_dir() / 'application-a',
	metadata18_runtime / 'application-a', '--profiles'] + application18_profiles + application18_arguments,
	depends: astrac, timeout: 600, is_parallel: false, workdir: meson.project_source_root())
test('optimizer-hardening-18-journal-b1-regression', ints_python,
	args: [files('b1/qualify.py'), astrac, meson.current_build_dir() / 'journal-b1',
	metadata18_runtime / 'journal-b1', '--profiles'] + application18_profiles + application18_arguments,
	depends: astrac, timeout: 600, is_parallel: false, workdir: meson.project_source_root())
test('optimizer-hardening-18-application-b2', ints_python,
	args: [files('b2/qualify.py'), astrac, meson.current_build_dir() / 'application-b2',
	metadata18_runtime / 'application-b2', '--profiles'] + application18_profiles + application18_arguments,
	depends: astrac, timeout: 600, is_parallel: false, workdir: meson.project_source_root())
