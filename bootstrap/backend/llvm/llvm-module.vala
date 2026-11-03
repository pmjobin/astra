// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

namespace Astra.Backend.LLVM {
public errordomain LlvmError {
	INVALID_INPUT,
	LOWERING,
	VERIFICATION,
	TARGET,
	EMISSION
}

// Owns only LLVM resources. No upstream graph or provenance is retained.
public class LlvmModuleArtifact : Object {
	internal string selected_target = "host";
	internal bool requires_policy_runtime;
	internal bool requires_policy_heap;
	internal HashTable<string, void*> allocation_domains = new HashTable<string, void*> (str_hash, str_equal);
	internal HashTable<string, string> allocation_tags = new HashTable<string, string> (str_hash, str_equal);
	internal GenericArray<LlvmPolicyGlobalBinding> allocation_globals = new GenericArray<LlvmPolicyGlobalBinding> ();
	internal bool requires_pc_devices;
	internal GenericArray<LlvmPcAtomicBinding> pc_atomics = new GenericArray<LlvmPcAtomicBinding> ();
	internal GenericArray<LlvmSharedAtomicBinding> shared_atomics = new GenericArray<LlvmSharedAtomicBinding> ();
	internal GenericArray<LlvmSumSequence> concurrency_guards = new GenericArray<LlvmSumSequence> ();
	internal GenericArray<LlvmSumSequence> c_union_guards = new GenericArray<LlvmSumSequence> ();
	internal HashTable<string, void*> concurrency_symbols = new HashTable<string, void*> (str_hash, str_equal);
	internal bool semantic_optimizations;
	internal GenericArray<LlvmUniqueReceiverBinding> unique_receivers = new GenericArray<LlvmUniqueReceiverBinding> ();
	internal GenericArray<LlvmEffectBinding> effects = new GenericArray<LlvmEffectBinding> ();
	internal GenericArray<LlvmVectorMemoryBinding> vector_memory = new GenericArray<LlvmVectorMemoryBinding> ();
	internal uint floating_permissions;
	internal GenericArray<LlvmFloatingPermission> floating_instructions = new GenericArray<LlvmFloatingPermission> ();
	internal LlvmRuntimeProfile? runtime_profile;
	internal GenericArray<LlvmVolatileAccess> volatile_accesses = new GenericArray<LlvmVolatileAccess> ();
	internal GenericArray<LlvmSaturationBinding> saturations = new GenericArray<LlvmSaturationBinding> ();
	internal LlvmDebugInfo? debug_info;
	internal GenericArray<LlvmNativeModuleBinding> native_modules = new GenericArray<LlvmNativeModuleBinding> ();
	internal GenericArray<LlvmLazyGateBinding> lazy_gates = new GenericArray<LlvmLazyGateBinding> ();
	internal GenericArray<LlvmAsyncFrameBinding> async_frames = new GenericArray<LlvmAsyncFrameBinding> ();
	internal HashTable<string, void*> retained_runtime_symbols = new HashTable<string, void*> (str_hash, str_equal);
	internal HashTable<string, void*> retained_helpers = new HashTable<string, void*> (str_hash, str_equal);
	internal HashTable<string, void*> callback_views = new HashTable<string, void*> (str_hash, str_equal);
	internal GenericArray<LlvmCallbackCBoolBinding> callback_c_bool = new GenericArray<LlvmCallbackCBoolBinding> ();
	internal GenericArray<LlvmRetainedHelperBinding> retained_bindings = new GenericArray<LlvmRetainedHelperBinding> ();
	internal HashTable<string, void*> async_runtime_symbols = new HashTable<string, void*> (str_hash, str_equal);
	internal GenericArray<LlvmSlotsLayoutBinding> slots_layouts = new GenericArray<LlvmSlotsLayoutBinding> ();
	internal HashTable<string, void*> slots_helpers = new HashTable<string, void*> (str_hash, str_equal);
	internal GenericArray<LlvmClassLayoutBinding> class_layouts = new GenericArray<LlvmClassLayoutBinding> ();
	internal GenericArray<LlvmPodLayoutBinding> pod_layouts = new GenericArray<LlvmPodLayoutBinding> ();
	internal GenericArray<LlvmClassGlobalBinding> class_globals = new GenericArray<LlvmClassGlobalBinding> ();
	internal HashTable<int, LlvmScopedDescriptorAuthority> scoped_descriptors = new HashTable<int, LlvmScopedDescriptorAuthority> (direct_hash, direct_equal);
	private HashTable<int, void*> class_constructors = new HashTable<int, void*> (direct_hash, direct_equal);
	private HashTable<int, void*> class_destructors = new HashTable<int, void*> (direct_hash, direct_equal);
	internal void bind_class_lifecycle(NativeAbi.NativeFunction source, CApi.ValueRef function) throws LlvmError {
		if (!source.declaring_type_is_class || source.kind != NativeAbi.NativeCallableKind.CONSTRUCTOR && source.kind != NativeAbi.NativeCallableKind.DESTRUCTOR) {
			return;
		}
		var targets = source.kind == NativeAbi.NativeCallableKind.CONSTRUCTOR ? class_constructors : class_destructors;
		if (source.declaring_type_ordinal < 0 || targets.contains (source.declaring_type_ordinal)) {
			throw new LlvmError.LOWERING ("Class lifecycle requires its unique native declaration role");
		}
		targets.insert (source.declaring_type_ordinal, (void*) function);
	}

	internal CApi.ValueRef class_constructor(int ordinal) {
		return (CApi.ValueRef) class_constructors.lookup (ordinal);
	}

	internal CApi.ValueRef class_destructor(int ordinal) {
		return (CApi.ValueRef) class_destructors.lookup (ordinal);
	}

	internal GenericArray<LlvmClassFunctionBinding> class_functions = new GenericArray<LlvmClassFunctionBinding> ();
	internal GenericArray<LlvmForeignFunctionBinding> foreign_functions = new GenericArray<LlvmForeignFunctionBinding> ();
	internal GenericArray<LlvmForeignRecordLayoutBinding> foreign_records = new GenericArray<LlvmForeignRecordLayoutBinding> ();
	internal HashTable<string, void*> foreign_runtime_symbols = new HashTable<string, void*> (str_hash, str_equal);
	internal GenericArray<LlvmClassAddressBinding> class_addresses = new GenericArray<LlvmClassAddressBinding> ();
	internal GenericArray<LlvmClassValueBinding> class_values = new GenericArray<LlvmClassValueBinding> ();
	internal GenericArray<LlvmClassCallBinding> class_calls = new GenericArray<LlvmClassCallBinding> ();
	internal GenericArray<LlvmScopedBackingBinding> scoped_backings = new GenericArray<LlvmScopedBackingBinding> ();
	private GenericArray<LlvmScopedBackingBinding> scoped_backing_origins = new GenericArray<LlvmScopedBackingBinding> ();
	private bool scope_contracts_sealed;
	internal void bind_scoped_backing(LlvmScopedBackingBinding binding) throws LlvmError {
		if (scope_contracts_sealed) {
			throw new LlvmError.LOWERING ("scoped backing inventory is already sealed");
		}
		scoped_backings.add (binding);
		scoped_backing_origins.add (binding);
	}

	private HashTable<void*, LlvmScopedBorrowBinding> scoped_borrows = new HashTable<void*, LlvmScopedBorrowBinding> (direct_hash, direct_equal);
	private HashTable<void*, LlvmScopedClassLoans> scoped_class_loans = new HashTable<void*, LlvmScopedClassLoans> (direct_hash, direct_equal);
	internal bool has_scoped_class_loans(CApi.ValueRef function) {
		return scoped_class_loans.contains ((void*) function);
	}

	private HashTable<void*, LlvmScopedOwnedInputs> scoped_owned_inputs = new HashTable<void*, LlvmScopedOwnedInputs> (direct_hash, direct_equal);
	internal bool has_scoped_owned_inputs(CApi.ValueRef function) {
		return scoped_owned_inputs.contains ((void*) function);
	}

	private HashTable<void*, LlvmScopedFreshResult> scoped_fresh_results = new HashTable<void*, LlvmScopedFreshResult> (direct_hash, direct_equal);
	internal bool has_scoped_fresh_result(CApi.ValueRef function) {
		return scoped_fresh_results.contains ((void*) function);
	}

	internal void bind_scoped_owned_inputs(CApi.ValueRef function, CApi.TypeRef type, NativeAbi.NativeFunction source, NativeAbi.NativeAbiProgram program, LlvmStructRegistry structs) throws LlvmError {
		if (scope_contracts_sealed) {
			throw new LlvmError.LOWERING ("owned scoped input inventory is already sealed");
		}
		var contract = LlvmScopedOwnedInputs.from_native (this, function, type, source, program, structs);
		var fresh = LlvmScopedFreshResult.from_native (this, function, type, source, program.classes, structs);
		if (fresh != null) {
			if (has_scoped_fresh_result (function)) {
				throw new LlvmError.LOWERING ("fresh scoped result binds once");
			}
			scoped_fresh_results.insert ((void*) function, fresh);
		}
		if (contract == null && fresh == null && LlvmScopedOwnedInputs.required (source.signature, program)) {
			var loans = scoped_class_loans.lookup ((void*) function);
			if (loans == null || !loans.covers_record_borrows (this, source.signature, program)) {
				throw new LlvmError.LOWERING ("scoped formal requires its complete emitted ABI authority: %s", source.name);
			}
		}
		if (contract != null) {
			if (has_scoped_owned_inputs (function)) {
				throw new LlvmError.LOWERING ("owned scoped input binds once");
			}
			scoped_owned_inputs.insert ((void*) function, contract);
		}
	}

	internal void bind_scoped_imported_values(CApi.ValueRef function, CApi.TypeRef type, NativeAbi.NativeFunction source, NativeAbi.NativeAbiProgram program, LlvmStructRegistry structs, string symbol) throws LlvmError {
		bool required = LlvmScopedOwnedInputs.required (source.signature, program);
		if (source.declaring_type_is_class && source.declaring_type_ordinal >= 0 && source.declaring_type_ordinal < program.classes.length) {
			required = required || LlvmScopedClassGraph.contains_scope (program.classes[source.declaring_type_ordinal], program);
		}
		if (!required) {
			return;
		}
		var binding = new LlvmNativeModuleBinding (function, type, symbol, true);
		binding.verify ();
		bind_scoped_borrow (function, type, source, program, structs);
		bind_scoped_owned_inputs (function, type, source, program, structs);
		var borrowed = scoped_borrows.lookup ((void*) function);
		if (borrowed != null) {
			borrowed.attach_import (binding);
		}
		var loans = scoped_class_loans.lookup ((void*) function);
		if (loans != null) {
			loans.attach_import (binding);
		}
		var contexts = scoped_inputs.lookup ((void*) function);
		if (contexts != null) {
			contexts.attach_import (binding);
		}
		var owners = scoped_owned_inputs.lookup ((void*) function);
		if (owners != null) {
			owners.attach_import (binding);
		}
		var fresh = scoped_fresh_results.lookup ((void*) function);
		if (fresh != null) {
			fresh.attach_import (binding);
		}
	}

	private GenericArray<LlvmAsyncFrameBinding> scoped_coroutines = new GenericArray<LlvmAsyncFrameBinding> ();
	internal void bind_scoped_coroutine(LlvmAsyncFrameBinding frame) throws LlvmError {
		if (scope_contracts_sealed || scoped_coroutines.find (frame) || frame.scoped_captures == null) {
			throw new LlvmError.LOWERING ("scoped coroutine inventory binds each original frame once");
		}
		scoped_coroutines.add (frame);
	}

	private GenericArray<LlvmScopedImportedTask> scoped_task_imports = new GenericArray<LlvmScopedImportedTask> ();
	internal LlvmScopedImportedTask? bind_scoped_imported_task(NativeAbi.NativeFunction source, NativeAbi.NativeAbiProgram program, LlvmStructRegistry structs, CApi.ValueRef factory, CApi.ValueRef checked_factory, CApi.TypeRef type, string symbol) throws LlvmError {
		if (scope_contracts_sealed) {
			throw new LlvmError.LOWERING ("opaque scoped task inventory is already sealed");
		}
		var contract = LlvmScopedImportedTask.from_native (this, source, program, structs, factory, checked_factory, type, symbol);
		if (contract != null) {
			scoped_task_imports.add (contract);
		}
		return contract;
	}

	internal void bind_scoped_imported_capture(CApi.ValueRef instruction, LlvmScopedImportedTask imported, CApi.ValueRef factory, CApi.TypeRef type, CApi.ValueRef[] arguments, bool checked_admission) throws LlvmError {
		if (scope_contracts_sealed || !scoped_task_imports.find (imported) || scoped_captured_tasks.contains ((void*) instruction)) {
			throw new LlvmError.LOWERING ("opaque scoped captured task requires its original admitted import");
		}
		scoped_captured_tasks.insert ((void*) instruction, new LlvmScopedCapturedTask.opaque (instruction, imported, factory, type, arguments, checked_admission));
	}

	private HashTable<void*, LlvmScopedCapturedTask> scoped_captured_tasks = new HashTable<void*, LlvmScopedCapturedTask> (direct_hash, direct_equal);
	internal void bind_scoped_captured_task(CApi.ValueRef instruction, LlvmAsyncFrameBinding frame, CApi.ValueRef factory, CApi.TypeRef type, CApi.ValueRef[] arguments, bool checked_admission) throws LlvmError {
		if (scope_contracts_sealed || scoped_captured_tasks.contains ((void*) instruction)) {
			throw new LlvmError.LOWERING ("scoped captured task binds once before sealing");
		}
		scoped_captured_tasks.insert ((void*) instruction, new LlvmScopedCapturedTask (instruction, frame, factory, type, arguments, checked_admission));
	}

	private HashTable<void*, LlvmScopedTaskFrame> scoped_task_frames = new HashTable<void*, LlvmScopedTaskFrame> (direct_hash, direct_equal);
	internal void bind_scoped_task_frame(CApi.ValueRef instruction, CApi.ValueRef factory, CApi.TypeRef type, CApi.ValueRef[] arguments) throws LlvmError {
		if (scope_contracts_sealed || scoped_task_frames.contains ((void*) instruction)) {
			throw new LlvmError.LOWERING ("scoped task frame association binds once before scope sealing");
		}
		scoped_task_frames.insert ((void*) instruction, new LlvmScopedTaskFrame (instruction, factory, type, arguments));
	}

	private HashTable<void*, LlvmScopedContextInputs> scoped_inputs = new HashTable<void*, LlvmScopedContextInputs> (direct_hash, direct_equal);
	internal bool scoped_borrow(CApi.ValueRef function) {
		return scoped_borrows.contains ((void*) function);
	}

	internal bool has_scoped_context_inputs(CApi.ValueRef function) {
		return scoped_inputs.contains ((void*) function);
	}

	internal void bind_scoped_borrow(CApi.ValueRef function, CApi.TypeRef type, NativeAbi.NativeFunction source, NativeAbi.NativeAbiProgram program, LlvmStructRegistry structs) throws LlvmError {
		var classes = program.classes;
		if (scope_contracts_sealed) {
			throw new LlvmError.LOWERING ("scoped borrow inventory is already sealed");
		}
		var class_loans = LlvmScopedClassLoans.from_native (this, function, type, source, classes, structs);
		if (class_loans == null) {
			foreach (var parameter in source.signature.parameters) {
				int ordinal = parameter.borrowed_class_ordinal;
				if (ordinal >= 0 && ordinal < classes.length) {
					var policy = classes[ordinal].allocation_policy;
					if (policy != null && policy.kind == Astra.Source.AllocationKind.CONTEXT && policy.context_mode == "scoped-affine") {
						throw new LlvmError.LOWERING ("scoped Class borrow requires its complete emitted loan authority");
					}
				}
			}
		}
		if (class_loans != null) {
			if (scoped_class_loans.contains ((void*) function)) {
				throw new LlvmError.LOWERING ("scoped Class loans bind once");
			}
			scoped_class_loans.insert ((void*) function, class_loans);
		}
		var contract = LlvmScopedBorrowBinding.from_native (this, function, type, source, program, structs);
		if (contract != null) {
			if (scoped_borrow (function)) {
				throw new LlvmError.LOWERING ("scoped native borrow binds once");
			}
			scoped_borrows.insert ((void*) function, contract);
		}
		var inputs = LlvmScopedContextInputs.from_native (function, type, source, classes);
		if (inputs == null) {
			foreach (var parameter in source.signature.parameters) {
				var context = parameter.abi_type as NativeAbi.NativeContextHandleType;
				if (context != null && context.mode == "scoped-affine") {
					throw new LlvmError.LOWERING ("scoped formal requires its complete emitted ABI authority: %s", source.name);
				}
			}
		}
		if (inputs != null) {
			if (has_scoped_context_inputs (function)) {
				throw new LlvmError.LOWERING ("scoped context input binds once");
			}
			scoped_inputs.insert ((void*) function, inputs);
		}
	}

	internal void seal_scoped_borrows() throws LlvmError {
		if (scope_contracts_sealed) {
			throw new LlvmError.LOWERING ("scoped lifetime inventories seal once");
		}
		foreach (var imported in scoped_task_imports) {
			imported.seal (scoped_descriptors);
		}
		foreach (var captured in scoped_captured_tasks.get_values ()) {
			captured.seal ();
		}
		foreach (var contract in scoped_borrows.get_values ()) {
			contract.seal ();
		}
		foreach (var loans in scoped_class_loans.get_values ()) {
			loans.seal ();
		}
		foreach (var inputs in scoped_inputs.get_values ()) {
			inputs.seal ();
		}
		foreach (var inputs in scoped_owned_inputs.get_values ()) {
			inputs.seal (scoped_descriptors);
		}
		foreach (var fresh in scoped_fresh_results.get_values ()) {
			fresh.seal ();
		}
		scope_contracts_sealed = true;
	}

	internal void verify_scoped_borrows() throws LlvmError {
		foreach (var contract in scoped_borrows.get_values ()) {
			contract.verify ();
		}
	}

	internal void verify_scoped_context_inputs() throws LlvmError {
		foreach (var inputs in scoped_inputs.get_values ()) {
			inputs.verify ();
		}
	}

	internal void verify_scoped_owned_inputs() throws LlvmError {
		foreach (var imported in scoped_task_imports) {
			imported.verify ();
		}
		foreach (var inputs in scoped_owned_inputs.get_values ()) {
			inputs.verify ();
		}
		foreach (var fresh in scoped_fresh_results.get_values ()) {
			fresh.verify ();
		}
	}

	internal void verify_scoped_allocations() throws LlvmError {
		foreach (var frame in scoped_coroutines) {
			if (!async_frames.find (frame)) {
				throw new LlvmError.VERIFICATION ("scoped coroutine lost its original complete frame inventory");
			}
		}
		foreach (var loans in scoped_class_loans.get_values ()) {
			loans.verify (scoped_borrows, scoped_class_loans);
		}
		LlvmScopedAllocationVerifier.verify (module, scoped_borrows, scoped_inputs, scoped_owned_inputs, scoped_class_loans, scoped_fresh_results, scoped_task_frames, scoped_coroutines, scoped_captured_tasks);
	}

	private void verify_scoped_factories() throws LlvmError {
		var expected = new HashTable<void*, bool> (direct_hash, direct_equal);
		foreach (var binding in scoped_backings) {
			void* factory = (void*) binding.actual_factory ();
			if (factory == null || expected.contains (factory)) {
				throw new LlvmError.VERIFICATION ("scoped factory lost its unique backing-loan authority");
			}
			expected.insert (factory, true);
		}
		var seen = new HashTable<void*, bool> (direct_hash, direct_equal);
		for (var function = CApi.first_function (module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
						continue;
					}
					var target = CApi.called_value (instruction);
					if ((void*) CApi.is_function (target) == null) {
						continue;
					}
					size_t length;
					if (CApi.value_name (target, out length) != "astra_context17_open_scoped") {
						continue;
					}
					if (!expected.contains ((void*) instruction)) {
						throw new LlvmError.VERIFICATION ("unregistered emitted scoped factory lacks its backing-loan proof");
					}
					seen.insert ((void*) instruction, true);
				}
			}
		}
		if (seen.size () != expected.size ()) {
			throw new LlvmError.VERIFICATION ("scoped factory inventory lost its original emitted backing-loan acquisition");
		}
		if (scoped_backings.length != scoped_backing_origins.length || scoped_backings.length != 0 && !scope_contracts_sealed) {
			throw new LlvmError.VERIFICATION ("scoped factory inventory lost its original admitted backing-loan identity");
		}
		for (int b = 0; b < scoped_backings.length; b++) {
			if (scoped_backings[b] != scoped_backing_origins[b]) {
				throw new LlvmError.VERIFICATION ("scoped factory inventory lost its original admitted backing-loan identity");
			}
		}
	}

	internal GenericArray<LlvmClassBranchBinding> class_branches = new GenericArray<LlvmClassBranchBinding> ();
	internal GenericArray<LlvmClassPhiBinding> class_phis = new GenericArray<LlvmClassPhiBinding> ();
	internal GenericArray<LlvmClassAllocationBinding> class_allocations = new GenericArray<LlvmClassAllocationBinding> ();
	internal GenericArray<LlvmSumSequence> foreign_imports = new GenericArray<LlvmSumSequence> ();
	internal GenericArray<LlvmSumSequence> constructor_unwinds = new GenericArray<LlvmSumSequence> ();
	internal LlvmTargetMachineArtifact? class_target;
	internal LlvmTargetMachineArtifact? sum_target;
	internal string sum_target_triple = "";
	internal string sum_data_layout = "";
	internal GenericArray<LlvmSumSequence> sum_sequences = new GenericArray<LlvmSumSequence> ();
	internal GenericArray<LlvmForeignSignalBinding> foreign_signals = new GenericArray<LlvmForeignSignalBinding> ();
	internal GenericArray<LlvmSumLayout> sum_layouts = new GenericArray<LlvmSumLayout> ();
	internal GenericArray<LlvmSumProjection> sum_projections = new GenericArray<LlvmSumProjection> ();
	internal GenericArray<LlvmSumAccess> sum_accesses = new GenericArray<LlvmSumAccess> ();
	internal GenericArray<LlvmSumClear> sum_clears = new GenericArray<LlvmSumClear> ();
	internal GenericArray<LlvmSumCopy> sum_copies = new GenericArray<LlvmSumCopy> ();
	internal GenericArray<LlvmSumAddress> sum_addresses = new GenericArray<LlvmSumAddress> ();
	internal GenericArray<LlvmSumRead> sum_reads = new GenericArray<LlvmSumRead> ();
	internal GenericArray<LlvmSumDispatch> sum_dispatches = new GenericArray<LlvmSumDispatch> ();
	internal GenericArray<LlvmSumCall> sum_calls = new GenericArray<LlvmSumCall> ();
	internal int continuation_family_count;
	internal GenericArray<LlvmContinuationCallBinding> continuation_calls = new GenericArray<LlvmContinuationCallBinding> ();
	internal GenericArray<LlvmContinuationPublicationBinding> continuation_publications = new GenericArray<LlvmContinuationPublicationBinding> ();
	internal GenericArray<LlvmContinuationMoveBinding> continuation_moves = new GenericArray<LlvmContinuationMoveBinding> ();
	internal GenericArray<LlvmContinuationEnvironmentBinding> continuation_environments = new GenericArray<LlvmContinuationEnvironmentBinding> ();
	internal CApi.ContextRef context;
	internal CApi.ModuleRef module;
	// Borrowed LLVM identities only; never retain the selected SSA function.
	internal CApi.ValueRef entry_function;
	internal CApi.TypeRef entry_type;
	internal NativeAbi.NativeEntryKind entry_kind;
	internal NativeAbi.NativeTextSliceLayout? text_slice_layout;
	internal bool requires_text_slices;
	private bool has_launch_wrapper;
	internal bool requires_binary32;
	internal bool requires_binary64;
	internal bool requires_c_text;
	internal bool requires_c_floating;
	internal bool requires_c_buffer;
	internal bool requires_c_wide;
	internal bool requires_c_bool;
	internal bool requires_native_wide;
	internal bool windows_interop_validated { get; private set; }
	internal bool windows_declarations { get; private set; }
	internal void admit_windows_interop(Astra.Ssa.SsaProgram source, bool native_modules = false) throws LlvmError {
		if (selected_target != LlvmTargetMachineArtifact.WINDOWS_INTEROP) {
			throw new LlvmError.INVALID_INPUT ("Windows source admission requires its exact selected target");
		}
		LlvmWindowsInteropProfile.validate_source (source, native_modules);
		windows_declarations = LlvmWindowsInteropProfile.declarations (source) || native_modules;
		windows_interop_validated = true;
	}

	internal bool requires_vectors;
	internal bool requires_hosted_buffers;
	internal GenericArray<LlvmRecordLayoutBinding> record_layouts = new GenericArray<LlvmRecordLayoutBinding> ();
	internal GenericArray<LlvmCFunctionBinding> c_imports = new GenericArray<LlvmCFunctionBinding> ();
	internal GenericArray<LlvmCExportBinding> c_exports = new GenericArray<LlvmCExportBinding> ();
	internal GenericArray<LlvmCRecordStackSlot> c_record_slots = new GenericArray<LlvmCRecordStackSlot> ();
	internal GenericArray<LlvmCRecordLayoutBinding> c_records = new GenericArray<LlvmCRecordLayoutBinding> ();
	internal GenericArray<LlvmCCallbackBinding> c_callbacks = new GenericArray<LlvmCCallbackBinding> ();
	internal LlvmTargetMachineArtifact? c_record_target;
	internal GenericArray<LlvmBufferExchangeBinding> buffer_exchanges = new GenericArray<LlvmBufferExchangeBinding> ();
	internal HashTable<string, LlvmTypeLayout> type_layouts = new HashTable<string, LlvmTypeLayout> (str_hash, str_equal);

	internal LlvmModuleArtifact () {
		context = CApi.context_create ();
		module = CApi.module_create_with_name_in_context ("astra.scalar", context);
	}

	~LlvmModuleArtifact () {
		debug_info = null;
		type_layouts.remove_all ();
		CApi.dispose_module (module);
		CApi.context_dispose (context);
	}

	public void verify() throws LlvmError {
		bool c_bool = false;
		foreach (var imported in c_imports) {
			c_bool |= imported.requires_c_bool;
		}
		foreach (var exported in c_exports) {
			c_bool |= exported.requires_c_bool;
		}
		foreach (var callback in callback_c_bool) {
			c_bool |= callback.requires_c_bool;
			callback.verify ();
		}
		if (requires_c_bool != c_bool) {
			throw new LlvmError.VERIFICATION ("C99 bool lost its exact physical target requirement");
		}
		foreach (var sequence in c_union_guards) {
			sequence.verify ();
		}
		foreach (var function in foreign_functions) {
			function.verify ();
		}
		foreach (var record in foreign_records) {
			if (class_target == null) {
				throw new LlvmError.VERIFICATION ("foreign POD lost its exact target layout witness");
			}
			record.verify (class_target.enum_target_data (this));
		}
		foreach (var symbol in foreign_runtime_symbols.get_keys ()) {
			var target = CApi.named_function (module, symbol);
			if ((void*) target != (void*) foreign_runtime_symbols.lookup (symbol) || CApi.count_basic_blocks (target) != 0 || CApi.function_call_conv (target) != CApi.CallConv.C) {
				throw new LlvmError.VERIFICATION ("foreign runtime lost its exact compiler-private provider identity");
			}
		}
		foreach (var guard in concurrency_guards) {
			guard.verify ();
		}
		foreach (var name in concurrency_symbols.get_keys ()) {
			var target = CApi.named_function (module, name);
			if ((void*) target != (void*) concurrency_symbols.lookup (name) || CApi.count_basic_blocks (target) != 0 || CApi.function_call_conv (target) != CApi.CallConv.C) {
				throw new LlvmError.VERIFICATION ("concurrency runtime lost its exact provider identity");
			}
		}
		foreach (var binding in shared_atomics) {
			binding.verify ();
		}
		if (requires_policy_runtime != (allocation_domains.size () > 0)) {
			throw new LlvmError.VERIFICATION ("allocator runtime requirement lost its exact domain authority");
		}
		foreach (var global in allocation_globals) {
			global.verify ();
		}
		foreach (var operation in pc_atomics) {
			operation.verify ();
		}
		var unique_calls = new HashTable<void*, bool> (direct_hash, direct_equal);
		foreach (var binding in unique_receivers) {
			binding.verify ();
			unique_calls.insert ((void*) binding.call, true);
		}
		for (var function = CApi.first_function (module); (void*) function != null; function = CApi.next_function (function)) {
			for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
				for (var instruction = CApi.first_instruction (block); (void*) instruction != null; instruction = CApi.next_instruction (instruction)) {
					if (CApi.opcode (instruction) != CApi.Opcode.CALL) {
						continue;
					}
					for (uint p = 0; p <= CApi.argument_count (instruction); p++) {
						if ((void*) CApi.call_enum_attribute (instruction, p, CApi.enum_attribute_kind ("noalias", 7)) != null && (p != 1 || !unique_calls.contains ((void*) instruction))) {
							throw new LlvmError.VERIFICATION ("call gained a noalias claim without an exclusive local root");
						}
					}
				}
			}
		}
		foreach (var effect in effects) {
			effect.verify ();
		}
		foreach (var memory in vector_memory) {
			memory.verify ();
		}
		if (runtime_profile != null) {
			LlvmRuntimeProfile.verify_module (module, requires_policy_runtime);
		}
		foreach (var access in volatile_accesses) {
			access.verify ();
		}
		foreach (var saturation in saturations) {
			saturation.verify ();
		}
		LlvmStrictFloating.verify (module, floating_permissions, floating_instructions);
		foreach (var binding in native_modules) {
			binding.verify ();
		}
		if (debug_info != null) {
			debug_info.verify ();
		}
		foreach (var callback in c_callbacks) {
			callback.verify ();
		}
		foreach (var slot in c_record_slots) {
			slot.verify ();
		}
		foreach (var record in c_records) {
			if (c_record_target == null) {
				throw new LlvmError.VERIFICATION ("C record requires exact LP64 target authority");
			}
			record.verify (c_record_target.enum_target_data (this));
		}
		foreach (var gate in lazy_gates) {
			gate.verify ();
		}
		foreach (var name in retained_runtime_symbols.get_keys ()) {
			var target = CApi.named_function (module, name);
			if ((void*) target != (void*) retained_runtime_symbols.lookup (name) || CApi.count_basic_blocks (target) != 0 || CApi.function_call_conv (target) != CApi.CallConv.C) {
				throw new LlvmError.VERIFICATION ("retained runtime operation lost exact external provider identity");
			}
		}
		foreach (var name in retained_helpers.get_keys ()) {
			if ((void*) CApi.named_function (module, name) != (void*) retained_helpers.lookup (name)) {
				throw new LlvmError.VERIFICATION ("retained runtime helper lost registered compiler identity");
			}
		}
		foreach (var binding in retained_bindings) {
			binding.verify ();
		}
		foreach (var name in async_runtime_symbols.get_keys ()) {
			var original = (void*) async_runtime_symbols.lookup (name);
			var target = CApi.named_function (module, name);
			if ((void*) target != original || CApi.count_basic_blocks (target) != 0) {
				throw new LlvmError.VERIFICATION ("virtual runtime operation lost exact external provider identity");
			}
		}
		foreach (var frame in async_frames) {
			frame.verify ();
		}
		foreach (var binding in class_addresses) {
			binding.verify ();
		}
		foreach (var binding in class_values) {
			binding.verify ();
		}
		foreach (var sequence in sum_sequences) {
			if (sequence.owns_values) {
				sequence.verify ();
			}
		}
		foreach (var binding in class_calls) {
			binding.verify ();
		}
		foreach (var binding in scoped_backings) {
			binding.verify ();
		}
		verify_scoped_factories ();
		verify_scoped_borrows ();
		verify_scoped_context_inputs ();
		verify_scoped_owned_inputs ();
		verify_scoped_allocations ();
		foreach (var binding in class_branches) {
			binding.verify ();
		}
		foreach (var binding in class_phis) {
			binding.verify ();
		}
		foreach (var binding in class_allocations) {
			if (class_target == null) {
				throw new LlvmError.VERIFICATION ("class allocation lost target extent/alignment authority");
			}
			binding.verify (class_target.enum_target_data (this));
		}
		foreach (var binding in foreign_imports) {
			binding.verify ();
		}
		foreach (var binding in foreign_signals) {
			binding.verify ();
		}
		foreach (var binding in constructor_unwinds) {
			binding.verify ();
		}
		foreach (var binding in slots_layouts) {
			if (class_target == null) {
				throw new LlvmError.VERIFICATION ("owner slots lost exact target layout authority");
			}
			binding.verify (class_target.enum_target_data (this));
		}
		foreach (var binding in class_layouts) {
			binding.verify ();
		}
		foreach (var binding in pod_layouts) {
			if (class_target == null) {
				throw new LlvmError.VERIFICATION ("POD layout lost its exact target");
			}
			binding.verify (class_target.enum_target_data (this));
		}
		foreach (var binding in class_globals) {
			binding.verify ();
		}
		foreach (var binding in class_functions) {
			binding.verify ();
		}
		if (sum_layouts.length != 0) {
			if (sum_target == null) {
				throw new LlvmError.VERIFICATION ("sum layout requires its exact target witness");
			}
			foreach (var layout in sum_layouts) {
				layout.verify (sum_target.enum_target_data (this));
			}
		}
		foreach (var sequence in sum_sequences) {
			if (!sequence.owns_values) {
				sequence.verify ();
			}
		}
		foreach (var projection in sum_projections) {
			projection.verify ();
		}
		foreach (var access in sum_accesses) {
			access.verify ();
		}
		foreach (var clear in sum_clears) {
			clear.verify ();
		}
		foreach (var copy in sum_copies) {
			copy.verify ();
		}
		foreach (var address in sum_addresses) {
			address.verify ();
		}
		foreach (var read in sum_reads) {
			read.verify ();
		}
		foreach (var dispatch in sum_dispatches) {
			dispatch.verify ();
		}
		foreach (var call in sum_calls) {
			call.verify ();
		}
		var origins = new HashTable<void*, LlvmContinuationEnvironmentBinding> (direct_hash, direct_equal);
		var allocations = new HashTable<void*, bool> (direct_hash, direct_equal);
		var ready = new HashTable<void*, void*> (direct_hash, direct_equal);
		foreach (var origin in continuation_environments) {
			origin.verify ();
			if (origins.contains ((void*) origin.descriptor) || (origin.family.environment != null && allocations.contains ((void*) origin.environment))) {
				throw new LlvmError.VERIFICATION ("continuation environments require distinct owner carriers and allocations");
			}
			origins.insert ((void*) origin.descriptor, origin);
			if (origin.family.environment != null) {
				allocations.insert ((void*) origin.environment, true);
			}
		}
		foreach (var publication in continuation_publications) {
			publication.verify ();
			if (origins.lookup ((void*) publication.descriptor) != publication.origin || ready.contains ((void*) publication.descriptor)) {
				throw new LlvmError.VERIFICATION ("continuation publication requires its unique initialized owner");
			}
			ready.insert ((void*) publication.descriptor, (void*) publication.stores[2]);
		}
		foreach (var move in continuation_moves) {
			move.verify ();
			var origin = origins.lookup ((void*) move.source);
			if (origin == null || !ready.contains ((void*) move.source) || origins.contains ((void*) move.destination) || !LlvmBufferExchangeOrder.precedes ((CApi.ValueRef) ready.lookup ((void*) move.source), move.snapshot)) {
				throw new LlvmError.VERIFICATION ("continuation move requires its published environment owner");
			}
			origins.insert ((void*) move.destination, origin);
			ready.insert ((void*) move.destination, (void*) move.disarm);
		}
		foreach (var continuation in continuation_calls) {
			continuation.verify ();
			var origin = origins.lookup ((void*) continuation.descriptor);
			var published = (CApi.ValueRef) ready.lookup ((void*) continuation.descriptor);
			if (origin == null || origin.region != continuation.plan || (void*) published == null || !LlvmBufferExchangeOrder.precedes (published, continuation.code_address) || !LlvmBufferExchangeOrder.precedes (published, continuation.environment_address) || !LlvmBufferExchangeOrder.precedes (continuation.code, continuation.call) || !LlvmBufferExchangeOrder.precedes (continuation.environment, continuation.call)) {
				throw new LlvmError.VERIFICATION ("continuation invocation requires its published or moved environment owner");
			}
		}
		foreach (var exchange in buffer_exchanges) {
			exchange.verify ();
		}
		foreach (var imported in c_imports) {
			imported.verify ();
		}
		foreach (var exported in c_exports) {
			exported.verify ();
		}
		char* message;
		int failed = CApi.verify_module (module, CApi.VerifierFailureAction.RETURN_STATUS, out message);
		string diagnostic = message == null ? "no diagnostic" : ((string) message).strip ();
		if (message != null) {
			CApi.dispose_message (message);
		}
		if (failed != 0) {
			throw new LlvmError.VERIFICATION ("internal LLVM verification error: %s", diagnostic);
		}
	}

	public string dump() throws LlvmError {
		verify ();
		char* message = CApi.print_module_to_string (module);
		string result = (string) message;
		CApi.dispose_message (message);
		return result;
	}

	public void configure_executable(LlvmTargetMachineArtifact target) throws LlvmError {
		if ((void*) entry_function == null || has_launch_wrapper) {
			throw new LlvmError.INVALID_INPUT ("internal LLVM entry error: expected one bound entry and no launch wrapper");
		}
		if ((void*) CApi.named_function (module, "main") != null) {
			throw new LlvmError.INVALID_INPUT ("C boundary symbol `main` conflicts with the executable entry wrapper");
		}
		target.configure (this);
		if (entry_kind == NativeAbi.NativeEntryKind.TEXT_ARGUMENTS) {
			LlvmArguments.emit (this);
			has_launch_wrapper = true;
			verify ();
			return;
		}
		var wrapper = CApi.add_function (module, "main", entry_type);
		CApi.set_linkage (wrapper, CApi.Linkage.EXTERNAL);
		CApi.set_function_call_conv (wrapper, CApi.CallConv.C);
		var block = CApi.append_basic_block_in_context (context, wrapper, "entry");
		var builder = CApi.create_builder_in_context (context);
		CApi.position_builder_at_end (builder, block);
		if (debug_info != null) {
			debug_info.attach_launch (wrapper, builder);
		}
		var result = CApi.build_call (builder, entry_type, entry_function, null, 0, "result");
		CApi.set_instruction_call_conv (result, LlvmLowering.CALL_CONVENTION);
		CApi.build_ret (builder, result);
		CApi.dispose_builder (builder);
		has_launch_wrapper = true;
		verify ();
	}

}
}
