# SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
runtime_lifetimes = executable('astra-runtime-lifetime-equations',
	files('lifetime-equations.vala') + runtime_lifetime_sources,
	dependencies: host_dependencies, vala_args: frontend_vala_args, c_args: frontend_c_args,
	override_options: ['optimization=2', 'werror=true'])
test('runtime-composition-17-lifetime-equations', runtime_lifetimes,
	args: ['--tap'], protocol: 'tap', timeout: 30, workdir: meson.project_source_root())
runtime_lifetime_source = executable('astra-runtime-lifetime-source', files('lifetime-source.vala'),
	dependencies: vapi_dependency, vala_args: frontend_vala_args, c_args: frontend_c_args,
	override_options: ['optimization=2', 'werror=true'])
test('runtime-composition-17-lifetime-source', runtime_lifetime_source,
	args: ['--tap'], protocol: 'tap', timeout: 60, workdir: meson.project_source_root())
runtime_lifetime_core = executable('astra-runtime-lifetime-core', files('lifetime-core.vala'),
	dependencies: [core_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args,
	override_options: ['optimization=2', 'werror=true'])
test('runtime-composition-17-lifetime-core', runtime_lifetime_core,
	args: ['--tap'], protocol: 'tap', timeout: 60, workdir: meson.project_source_root())
test('runtime-composition-17-sequence-provider', ints_python,
	args: [files('sequence-provider.py'), astrac, meson.current_build_dir() / 'sequence-provider'],
	depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-query-provider', ints_python,
	args: [files('query-provider.py'), astrac, meson.current_build_dir() / 'query-provider'],
	depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-generic-buffer-domains', ints_python,
	args: [files('generic-buffer-domains.py'), astrac, meson.current_build_dir() / 'generic-buffer-domains'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-generic-owner-slots', ints_python,
	args: [files('generic-owner-slots.py'), astrac, meson.current_build_dir() / 'generic-owner-slots'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
runtime_lifetime_cfg = executable('astra-runtime-lifetime-cfg', files('lifetime-cfg.vala'),
	dependencies: [cfg_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args,
	override_options: ['optimization=2', 'werror=true'])
test('runtime-composition-17-lifetime-cfg', runtime_lifetime_cfg,
	args: ['--tap'], protocol: 'tap', timeout: 60, workdir: meson.project_source_root())
runtime_lifetime_ssa = executable('astra-runtime-lifetime-ssa', files('lifetime-ssa.vala'),
	dependencies: [ssa_dependency, vapi_dependency], vala_args: frontend_vala_args, c_args: frontend_c_args,
	# Native optimizer binding is consumed by the driver, excluded here. Keep
	# that unused-method warning visible in this detached lifetime helper.
	override_options: ['optimization=2', 'werror=false'])
test('runtime-composition-17-lifetime-ssa', runtime_lifetime_ssa,
	args: ['--tap'], protocol: 'tap', timeout: 60, workdir: meson.project_source_root())
test('runtime-composition-17-lifetime-units', ints_python,
	args: [files('lifetime-units.py'), astrac, meson.current_build_dir() / 'lifetime-sdk'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
foreach profile : ['single', 'pair', 'suspended-single', 'suspended-pair']
	test('runtime-composition-17-scoped-error-discard-' + profile, ints_python,
		args: [files('scoped-error-discard.py'), astrac, meson.current_build_dir() / ('scoped-error-discard-' + profile), profile],
		depends: astrac, timeout: 120, workdir: meson.project_source_root())
endforeach
test('runtime-composition-17-heap-catch-choices', ints_python,
	args: [files('heap-catch-choices.py'), astrac, meson.current_build_dir() / 'heap-catch-choices'],
	depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-mixed-error-choices', ints_python,
	args: [files('mixed-error-choices.py'), astrac, meson.current_build_dir() / 'mixed-error-choices'],
	depends: astrac, timeout: 120, workdir: meson.project_source_root())
foreach profile : ['local', 'borrowed', 'forwarded', 'await', 'await-catch', 'await-suspended']
	test('runtime-composition-17-host-scoped-errors-' + profile, ints_python,
		args: [files('host-scoped-errors.py'), astrac, meson.current_build_dir() / ('host-scoped-errors-' + profile), profile],
		depends: astrac, timeout: 120, workdir: meson.project_source_root())
endforeach
foreach profile : ['scalar', 'constructor', 'record']
	test('runtime-composition-17-opaque-scoped-tasks-' + profile, ints_python,
		args: [files('opaque-scoped-tasks.py'), astrac, meson.current_build_dir() / ('opaque-scoped-tasks-' + profile), profile],
		depends: astrac, timeout: 180, workdir: meson.project_source_root())
endforeach
foreach profile : ['host', 'await', 'await-suspended']
	test('runtime-composition-17-opaque-scoped-errors-' + profile, ints_python,
		args: [files('opaque-scoped-errors.py'), astrac, meson.current_build_dir() / ('opaque-scoped-errors-' + profile), profile],
		depends: astrac, timeout: 180, workdir: meson.project_source_root())
endforeach
foreach profile : ['heap', 'selected', 'alternate', 'empty']
	test('runtime-composition-17-mutable-scoped-fields-' + profile, ints_python,
		args: [files('mutable-scoped-fields.py'), astrac, meson.current_build_dir() / ('mutable-scoped-fields-' + profile), profile],
		depends: astrac, timeout: 120, workdir: meson.project_source_root())
endforeach
test('runtime-composition-17-mutable-scoped-field-units', ints_python,
	args: [files('mutable-scoped-field-units.py'), astrac, meson.current_build_dir() / 'mutable-scoped-field-units'],
	depends: astrac, timeout: 180, workdir: meson.project_source_root())
foreach profile : ['local', 'borrowed', 'forwarded', 'await', 'await-catch', 'await-suspended']
	test('runtime-composition-17-same-nominal-errors-' + profile, ints_python,
		args: [files('same-nominal-errors.py'), astrac, meson.current_build_dir() / ('same-nominal-errors-' + profile), profile],
		depends: astrac, timeout: 120, workdir: meson.project_source_root())
endforeach
foreach profile : ['host', 'await', 'await-suspended']
	test('runtime-composition-17-same-nominal-error-units-' + profile, ints_python,
		args: [files('same-nominal-error-units.py'), astrac, meson.current_build_dir() / ('same-nominal-error-units-' + profile), profile],
		depends: astrac, timeout: 180, workdir: meson.project_source_root())
endforeach
test('runtime-composition-17-same-nominal-sync', ints_python,
	args: [files('same-nominal-sync.py'), astrac, meson.current_build_dir() / 'same-nominal-sync'],
	depends: astrac, timeout: 120, workdir: meson.project_source_root())
context_proof = executable('astra-context-proof',
	['context-contracts.vala', 'lifetime-llvm.vala', '../../bootstrap/backend/llvm/capi/llvm-test.vapi'],
	dependencies: [llvm_backend_dependency, vapi_dependency],
	vala_args: frontend_vala_args, c_args: frontend_c_args)
test('runtime-composition-17-context-contracts', context_proof,
	args: ['--tap'], protocol: 'tap', timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-task-captures', ints_python, args: [files('scoped-task-captures.py'), astrac, meson.current_build_dir() / 'scoped-task-captures'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-record-task-captures', ints_python, args: [files('scoped-record-task-captures.py'), astrac, meson.current_build_dir() / 'scoped-record-task-captures'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
foreach profile : ['flat', 'nested', 'generic', 'empty', 'single-empty']
	test('runtime-composition-17-scoped-task-results-' + profile, ints_python, args: [files('scoped-task-results.py'), astrac, meson.current_build_dir() / ('scoped-task-results-' + profile), profile], depends: astrac, timeout: 120, workdir: meson.project_source_root())
endforeach
test('runtime-composition-17-mixed-empty-task-results', ints_python, args: [files('mixed-empty-task-results.py'), astrac, meson.current_build_dir() / 'mixed-empty-task-results'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-checked-scoped-task-captures', ints_python, args: [files('checked-scoped-task-captures.py'), astrac, meson.current_build_dir() / 'checked-scoped-task-captures'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-checked-scoped-record-captures', ints_python, args: [files('checked-scoped-task-captures.py'), astrac, meson.current_build_dir() / 'checked-scoped-record-captures', 'records'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-checked-scoped-generic-record-captures', ints_python, args: [files('checked-scoped-task-captures.py'), astrac, meson.current_build_dir() / 'checked-scoped-generic-record-captures', 'generic-records'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-checked-scoped-fieldless-captures', ints_python, args: [files('checked-scoped-task-captures.py'), astrac, meson.current_build_dir() / 'checked-scoped-fieldless-captures', 'fieldless'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-backing', ints_python, args: [files('scoped-backing.py'), astrac, meson.current_build_dir() / 'scoped-backing'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-scalar-length', ints_python, args: [files('scalar-length.py'), astrac, meson.current_build_dir() / 'scalar-length'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-fallible-lifetimes', ints_python, args: [files('fallible-lifetimes.py'), astrac, meson.current_build_dir() / 'fallible-lifetimes'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-argument-errors', ints_python, args: [files('argument-errors.py'), astrac, meson.current_build_dir() / 'argument-errors'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-backing-units', ints_python, args: [files('scoped-backing-units.py'), astrac, meson.current_build_dir() / 'scoped-backing-units'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-endpoints', ints_python, args: [files('endpoints.py'), astrac, meson.current_build_dir() / 'endpoints'], depends: astrac, timeout: 90, workdir: meson.project_source_root())
test('runtime-composition-17-context-substrate', ints_python, args: [files('contexts.py'), astrac, meson.current_build_dir() / 'contexts'], depends: astrac, timeout: 90, workdir: meson.project_source_root())
test('runtime-composition-17-context-owners', ints_python, args: [files('context-owners.py'), astrac, meson.current_build_dir() / 'context-owners'], depends: astrac, timeout: 90, workdir: meson.project_source_root())
test('runtime-composition-17-context-collections', ints_python, args: [files('context-collections.py'), astrac, meson.current_build_dir() / 'context-collections'], depends: astrac, timeout: 90, workdir: meson.project_source_root())
test('runtime-composition-17-context-associative', ints_python, args: [files('context-associative.py'), astrac, meson.current_build_dir() / 'context-associative'], depends: astrac, timeout: 90, workdir: meson.project_source_root())
test('runtime-composition-17-context-weak', ints_python, args: [files('context-weak.py'), astrac, meson.current_build_dir() / 'context-weak'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-context-constructors', ints_python, args: [files('context-constructors.py'), astrac, meson.current_build_dir() / 'context-constructors'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
foreach profile : ['direct', 'selected']
	test('runtime-composition-17-fallible-inputs-' + profile, ints_python, args: [files('context-fallible-inputs.py'), astrac, meson.current_build_dir() / ('fallible-inputs-' + profile), profile], depends: astrac, timeout: 180, workdir: meson.project_source_root())
	test('runtime-composition-17-fallible-buffers-' + profile, ints_python, args: [files('context-fallible-buffers.py'), astrac, meson.current_build_dir() / ('fallible-buffers-' + profile), profile], depends: astrac, timeout: 180, workdir: meson.project_source_root())
	test('runtime-composition-17-fallible-records-' + profile, ints_python, args: [files('context-fallible-records.py'), astrac, meson.current_build_dir() / ('fallible-records-' + profile), profile], depends: astrac, timeout: 180, workdir: meson.project_source_root())
endforeach
test('runtime-composition-17-constructor-buffer-units', ints_python, args: [files('constructor-buffer-units.py'), astrac, meson.current_build_dir() / 'constructor-buffer-units'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-constructor-record-units', ints_python, args: [files('constructor-buffer-units.py'), astrac, meson.current_build_dir() / 'constructor-record-units', 'records'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-owning-record', ints_python, args: [files('context-owning-record.py'), astrac, meson.current_build_dir() / 'context-owning-record'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-record-creation', ints_python, args: [files('record-creation.py'), astrac, meson.current_build_dir() / 'record-creation'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-classes', ints_python, args: [files('scoped-classes.py'), astrac, meson.current_build_dir() / 'scoped-classes'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-owning', ints_python, args: [files('scoped-owning.py'), astrac, meson.current_build_dir() / 'scoped-owning'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-graphs', ints_python, args: [files('scoped-graphs.py'), astrac, meson.current_build_dir() / 'scoped-graphs'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-constructor-rollback', ints_python, args: [files('scoped-constructor-rollback.py'), astrac, meson.current_build_dir() / 'scoped-constructor-rollback'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-owned-rollback', ints_python, args: [files('scoped-owned-rollback.py'), astrac, meson.current_build_dir() / 'scoped-owned-rollback'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-child-rollback', ints_python, args: [files('scoped-child-rollback.py'), astrac, meson.current_build_dir() / 'scoped-child-rollback'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-deep-rollback', ints_python, args: [files('scoped-deep-rollback.py'), astrac, meson.current_build_dir() / 'scoped-deep-rollback'], depends: astrac, timeout: 360, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-record-rollback', ints_python, args: [files('scoped-record-rollback.py'), astrac, meson.current_build_dir() / 'scoped-record-rollback'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-record-child-rollback', ints_python, args: [files('scoped-record-child-rollback.py'), astrac, meson.current_build_dir() / 'scoped-record-child-rollback'], depends: astrac, timeout: 900, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-factories', ints_python, args: [files('scoped-factories.py'), astrac, meson.current_build_dir() / 'scoped-factories'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-factory-units', ints_python, args: [files('scoped-factory-units.py'), astrac, meson.current_build_dir() / 'scoped-factory-units'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-buffer-graph-rollback', ints_python, args: [files('scoped-buffer-graph-rollback.py'), astrac, meson.current_build_dir() / 'scoped-buffer-graph-rollback'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-buffer-rollback', ints_python, args: [files('scoped-buffer-rollback.py'), astrac, meson.current_build_dir() / 'scoped-buffer-rollback'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-heap-rollback', ints_python, args: [files('scoped-heap-rollback.py'), astrac, meson.current_build_dir() / 'scoped-heap-rollback'], depends: astrac, timeout: 360, workdir: meson.project_source_root())
test('runtime-composition-17-record-units', ints_python, args: [files('context-record-units.py'), astrac, meson.current_build_dir() / 'context-record-units'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-record-units-mixed', ints_python, args: [files('context-record-units.py'), astrac, meson.current_build_dir() / 'context-record-units-mixed', 'mixed'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
foreach profile : ['direct', 'worker', 'affine', 'transfer', 'failure']
	test('runtime-composition-17-context-bytes-' + profile, ints_python, args: [files('context-bytes.py'), astrac, meson.current_build_dir() / ('context-bytes-' + profile), profile], depends: astrac, timeout: 180, workdir: meson.project_source_root())
endforeach
test('runtime-composition-17-byte-units', ints_python, args: [files('context-byte-units.py'), astrac, meson.current_build_dir() / 'context-byte-sdk'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-byte-views', ints_python, args: [files('context-byte-views.py'), astrac, meson.current_build_dir() / 'context-byte-views'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-endpoint-server', ints_python, args: [files('endpoint-server.py'), astrac, meson.current_build_dir() / 'endpoint-server'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-endpoint-errors', ints_python, args: [files('endpoint-errors.py'), astrac, meson.current_build_dir() / 'endpoint-errors'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-context-units', ints_python, args: [files('context-units.py'), astrac, meson.current_build_dir() / 'context-units'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
test('runtime-composition-17-context-workers', ints_python, args: [files('context-workers.py'), astrac, meson.current_build_dir() / 'context-workers'], depends: astrac, timeout: 90, workdir: meson.project_source_root())
test('runtime-composition-17-context-frames', ints_python, args: [files('context-frames.py'), astrac, meson.current_build_dir() / 'context-frames'], depends: astrac, timeout: 90, workdir: meson.project_source_root())
test('runtime-composition-17-borrowed-frame-contexts', ints_python, args: [files('borrowed-frame-contexts.py'), astrac, meson.current_build_dir() / 'borrowed-frame-contexts'], depends: astrac, timeout: 90, workdir: meson.project_source_root())
test('runtime-composition-17-borrowed-frame-units', ints_python, args: [files('borrowed-frame-units.py'), astrac, meson.current_build_dir() / 'borrowed-frame-units'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-scoped-frame-units', ints_python, args: [files('borrowed-frame-units.py'), astrac, meson.current_build_dir() / 'scoped-frame-units', 'scoped'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-frame-admission-substrate', ints_python, args: [files('frame-admission.py'), astrac, meson.current_build_dir() / 'frame-admission'], depends: astrac, timeout: 90, workdir: meson.project_source_root())
test('runtime-composition-17-checked-frames', ints_python, args: [files('checked-frames.py'), astrac, meson.current_build_dir() / 'checked-frames'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-checked-frame-units', ints_python, args: [files('checked-frame-units.py'), astrac, meson.current_build_dir() / 'checked-frame-units'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-checked-frame-buffers', ints_python, args: [files('checked-frame-buffers.py'), astrac, meson.current_build_dir() / 'checked-frame-buffers'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-checked-frame-buffer-units', ints_python, args: [files('checked-frame-units.py'), astrac, meson.current_build_dir() / 'checked-frame-buffer-units', 'buffers'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-checked-frame-records', ints_python, args: [files('checked-frame-records.py'), astrac, meson.current_build_dir() / 'checked-frame-records'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
test('runtime-composition-17-checked-frame-record-units', ints_python, args: [files('checked-frame-units.py'), astrac, meson.current_build_dir() / 'checked-frame-record-units', 'records'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
foreach profile : ['captures', 'results']
	test('runtime-composition-17-record-frames-' + profile, ints_python, args: [files('record-frames.py'), astrac, meson.current_build_dir() / ('record-frames-' + profile), profile], depends: astrac, timeout: 240, workdir: meson.project_source_root())
	test('runtime-composition-17-record-frame-units-' + profile, ints_python, args: [files('record-frame-units.py'), astrac, meson.current_build_dir() / ('record-frame-units-' + profile), profile], depends: astrac, timeout: 180, workdir: meson.project_source_root())
endforeach
test('runtime-composition-17-virtual-bridge', ints_python, args: [files('bridge-virtual.py'), astrac, meson.current_build_dir() / 'bridge-virtual'], depends: astrac, timeout: 90, workdir: meson.project_source_root())
if get_option('linux_async')
	test('runtime-composition-17-braid-provider', ints_python,
		args: [files('frozen-4/braid-provider.py'), astrac, meson.current_build_dir() / 'braid-provider', 'regression'],
		depends: astrac, timeout: 90, workdir: meson.project_source_root())
	foreach profile : ['application', 'sdk', 'operation']
		test('runtime-composition-17-braid-' + profile, ints_python,
			args: [files('frozen-4/braid-' + profile + '.py'), astrac, uring_prefix, meson.current_build_dir() / ('braid-' + profile), 'regression'],
			depends: astrac, timeout: 300, workdir: meson.project_source_root())
	endforeach
	test('runtime-composition-17-sequence-application', ints_python, args: [files('sequence-application.py'), astrac, uring_prefix, meson.current_build_dir() / 'sequence-application', 'regression'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
	test('runtime-composition-17-sequence-sdk', ints_python, args: [files('sequence-sdk.py'), astrac, uring_prefix, meson.current_build_dir() / 'sequence-sdk', 'regression'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
	test('runtime-composition-17-sequence-operation', ints_python, args: [files('sequence-operation.py'), astrac, uring_prefix, meson.current_build_dir() / 'sequence-operation', 'regression'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
	test('runtime-composition-17-query-regression', ints_python, args: [files('query-regression.py'), astrac, uring_prefix, meson.current_build_dir() / 'query-regression'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
	test('runtime-composition-17-stream-configuration', ints_python, args: [files('stream-configuration.py'), astrac, uring_prefix, meson.current_build_dir() / 'stream-configuration'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
	test('runtime-composition-17-stream-spool', ints_python, args: [files('stream-spool.py'), astrac, uring_prefix, meson.current_build_dir() / 'stream-qualified'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
	test('runtime-composition-17-stream-sdk', ints_python, args: [files('stream-sdk.py'), astrac, uring_prefix, meson.current_build_dir() / 'stream-sdk'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
	test('runtime-composition-17-stream-failures', ints_python, args: [files('stream-failures.py'), astrac, uring_prefix, meson.current_build_dir() / 'stream-failures'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
	test('runtime-composition-17-stream-safety', ints_python, args: [files('stream-safety.py'), astrac, uring_prefix, meson.current_build_dir() / 'stream-safety'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
	test('runtime-composition-17-context-nesting', ints_python, args: [files('context-nesting.py'), astrac, uring_prefix, meson.current_build_dir() / 'context-nesting'], depends: astrac, timeout: 300, workdir: meson.project_source_root())
	test('runtime-composition-17-source-cancellation', ints_python, args: [files('cancel-source.py'), astrac, uring_prefix, meson.current_build_dir() / 'cancel-source'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
	test('runtime-composition-17-byte-cancellation', ints_python, args: [files('cancel-source.py'), astrac, uring_prefix, meson.current_build_dir() / 'context-byte-cancellation', 'bytes'], depends: astrac, timeout: 240, workdir: meson.project_source_root())
	test('runtime-composition-17-bridge-protocol', ints_python, args: [files('bridge-protocol.py'), astrac, uring_prefix, meson.current_build_dir() / 'bridge-protocol'], depends: astrac, timeout: 120, workdir: meson.project_source_root())
	test('runtime-composition-17-public-bridge', ints_python, args: [files('bridge-public.py'), astrac, uring_prefix, meson.current_build_dir() / 'bridge-public'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
	test('runtime-composition-17-affine-home-retirement', ints_python, args: [files('affine-home-retirement.py'), astrac, uring_prefix, meson.current_build_dir() / 'affine-home-retirement'], depends: astrac, timeout: 180, workdir: meson.project_source_root())
endif
