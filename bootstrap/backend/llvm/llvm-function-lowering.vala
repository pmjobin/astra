// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Semantic;
using Astra.Source;
using Astra.Ssa;

namespace Astra.Backend.LLVM {
internal class LlvmBlockState : Object {
	internal CApi.BasicBlockRef primary;
	internal CApi.BasicBlockRef end;

	internal LlvmBlockState (CApi.BasicBlockRef primary) {
		this.primary = primary;
		this.end = primary;
	}

}

internal class LlvmFunctionLowering : Object {
	private SsaConstructor? unwind_constructor;
	private SsaConstructorAbort? unwind_recipe;
	private CApi.TypeRef unwind_stack_type;
	private CApi.ValueRef unwind_stack;
	private CApi.ValueRef unwind_count;
	private SsaReceiver? policy_receiver;
	private CApi.ValueRef monitor_guard;
	private bool guarded_c_union;

	private LlvmDebugScope? debug_scope;
	internal LlvmSumRegistry? sum_registry;
	private CApi.ValueRef sum_result;
	private HashTable<SsaEnumSlot, void*> enum_liveness = new HashTable<SsaEnumSlot, void*> (direct_hash, direct_equal);
	private HashTable<SsaEnumSlot, void*> enum_storage = new HashTable<SsaEnumSlot, void*> (direct_hash, direct_equal);
	internal HashTable<SsaContinuationRegion, NativeContinuationRegionPlan> continuations;
	internal GenericArray<LlvmFunctionBinding> continuation_targets;
	private LlvmTextLowering text;
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private LlvmFunctionBinding function;
	internal GenericArray<NativeScopedBackingPlan> scoped_plans = new GenericArray<NativeScopedBackingPlan> ();
	private HashTable<int, LlvmScopedBackingBinding> scoped_factories = new HashTable<int, LlvmScopedBackingBinding> (direct_hash, direct_equal);
	private HashTable<SsaCleanupInstruction, LlvmScopedBackingBinding> scoped_retirements = new HashTable<SsaCleanupInstruction, LlvmScopedBackingBinding> (direct_hash, direct_equal);
	private void scoped_access(SsaBufferStorage? storage, CApi.ValueRef instruction) {
		if (storage == null) {
			return;
		}
		foreach (var binding in scoped_factories.get_values ()) {
			if (binding.storage_ordinal == storage.ordinal) {
				binding.access (instruction);
			}
		}
	}

	private HashTable<SsaFunction, LlvmFunctionBinding> functions;
	private HashTable<SsaCFunction, CAbiFunction> c_correspondence;
	private HashTable<CAbiFunction, LlvmCFunctionBinding> c_functions;
	private HashTable<SsaBlock, LlvmBlockState> blocks = new HashTable<SsaBlock, LlvmBlockState> (direct_hash, direct_equal);
	// Borrowed LLVMValueRef pointers; the artifact owns their storage.
	private HashTable<SsaValue, void*> async_exception_slots = new HashTable<SsaValue, void*> (direct_hash, direct_equal);
	private HashTable<SsaValue, void*> values = new HashTable<SsaValue, void*> (direct_hash, direct_equal);
	private CApi.BuilderRef builder;
	private LlvmScalarLowering scalars;
	private LlvmStructRegistry structs;
	private LlvmClassRuntime classes;
	private LlvmRetainedLowering? retained_runtime;
	private LlvmRetainedLowering retained_lowering() throws LlvmError {
		if (retained_runtime == null) {
			retained_runtime = new LlvmRetainedLowering (artifact, types, builder, function.value, scalars);
		}
		return retained_runtime;
	}

	private LlvmClosureLowering? closure_runtime;
	private LlvmCallbackRuntime? callback_runtime;
	private LlvmCallbackRuntime callbacks() throws LlvmError {
		if (callback_runtime == null) {
			callback_runtime = new LlvmCallbackRuntime (artifact, types);
		}
		return callback_runtime;
	}

	private LlvmClosureLowering closure_lowering() throws LlvmError {
		if (closure_runtime == null) {
			closure_runtime = new LlvmClosureLowering (artifact, types, builder, function.value, scalars, buffer_allocator, functions, classes);
		}
		return closure_runtime;
	}

	private LlvmSharedLowering? shared_runtime;
	private LlvmSharedLowering shared_lowering() throws LlvmError {
		if (shared_runtime == null) {
			shared_runtime = new LlvmSharedLowering (artifact, types, builder, function.value, scalars, buffer_allocator, classes, functions);
		}
		return shared_runtime;
	}

	private HashTable<SsaObjectStorage, void*> object_storage = new HashTable<SsaObjectStorage, void*> (direct_hash, direct_equal);
	private HashTable<SsaObjectStorage, void*> singleton_initializers = new HashTable<SsaObjectStorage, void*> (direct_hash, direct_equal);
	private HashTable<SsaObjectStorage, bool> promoted_objects = new HashTable<SsaObjectStorage, bool> (direct_hash, direct_equal);
	private HashTable<SsaValue, bool> promoted_values = new HashTable<SsaValue, bool> (direct_hash, direct_equal);
	private HashTable<SsaSharedOperation, bool> elided_copies = new HashTable<SsaSharedOperation, bool> (direct_hash, direct_equal);
	private HashTable<SsaCleanupInstruction, bool> elided_releases = new HashTable<SsaCleanupInstruction, bool> (direct_hash, direct_equal);
	private HashTable<SsaAddressableLocal, void*> storage = new HashTable<SsaAddressableLocal, void*> (direct_hash, direct_equal);
	private int next_memory = 0;
	private HashTable<SsaBufferPair, SsaBufferStorage> async_buffer_reads = new HashTable<SsaBufferPair, SsaBufferStorage> (direct_hash, direct_equal);
	private HashTable<SsaBufferStorage, void*> buffer_storage = new HashTable<SsaBufferStorage, void*> (direct_hash, direct_equal);
	private HashTable<SsaBufferSlotCaptureInstruction, LlvmBufferSlotBinding> buffer_slots = new HashTable<SsaBufferSlotCaptureInstruction, LlvmBufferSlotBinding> (direct_hash, direct_equal);
	private HashTable<SsaBufferExchangeInstruction, LlvmBufferExchangePlan> buffer_exchanges = new HashTable<SsaBufferExchangeInstruction, LlvmBufferExchangePlan> (direct_hash, direct_equal);
	private HashTable<SsaBufferStorage, LlvmBufferLocalBinding> buffer_origins = new HashTable<SsaBufferStorage, LlvmBufferLocalBinding> (direct_hash, direct_equal);
	private HashTable<SsaValue, LlvmBufferReceiverBinding> buffer_receivers = new HashTable<SsaValue, LlvmBufferReceiverBinding> (direct_hash, direct_equal);
	private int function_ordinal;
	private SemanticType? lexical_field_owner;
	private SsaClass? async_error_class;
	private uint async_heap_owner_count;
	private CApi.BasicBlockRef async_entry;
	private CApi.ValueRef exception_success_slot;
	private HashTable<SsaCCallInstruction, GenericArray<void*>> c_record_slots = new HashTable<SsaCCallInstruction, GenericArray<void*>> (direct_hash, direct_equal);
	private HashTable<SsaClosureCall, void*> checked_closure_slots = new HashTable<SsaClosureCall, void*> (direct_hash, direct_equal);
	private HashTable<SsaCallInstruction, void*> exception_call_slots = new HashTable<SsaCallInstruction, void*> (direct_hash, direct_equal);
	private LlvmBufferAllocation buffer_allocator;
	private LlvmSlotsLowering owner_slots;
	private HashTable<SsaMemoryPlace, void*> record_addresses = new HashTable<SsaMemoryPlace, void*> (direct_hash, direct_equal);
	private HashTable<SsaMemoryPlace, void*> record_address_blocks = new HashTable<SsaMemoryPlace, void*> (direct_hash, direct_equal);
	private int next_cleanup = 0;
	private HashTable<SsaCleanupContract, CAbiCleanupFunction> cleanup_correspondence;
	private HashTable<CAbiCleanupFunction, LlvmCFunctionBinding> cleanup_functions;

	internal LlvmFunctionLowering (LlvmModuleArtifact artifact, LlvmTypeMapper types, LlvmFunctionBinding function, HashTable<SsaFunction, LlvmFunctionBinding> functions, HashTable<SsaCFunction, CAbiFunction> c_correspondence, HashTable<CAbiFunction, LlvmCFunctionBinding> c_functions, LlvmStructRegistry structs, HashTable<SsaCleanupContract, CAbiCleanupFunction> cleanup_correspondence, HashTable<CAbiCleanupFunction, LlvmCFunctionBinding> cleanup_functions, LlvmTextLowering text, LlvmClassRuntime classes) {
		this.text = text;
		this.classes = classes;
		this.artifact = artifact;
		this.types = types;
		this.function = function;
		this.functions = functions;
		this.c_correspondence = c_correspondence;
		this.c_functions = c_functions;
		this.structs = structs;
		this.cleanup_correspondence = cleanup_correspondence;
		this.cleanup_functions = cleanup_functions;
		builder = CApi.create_builder_in_context (artifact.context);
		scalars = new LlvmScalarLowering (artifact, types, builder, function.value);
		buffer_allocator = new LlvmBufferAllocation (artifact, builder, function.value, scalars);
		owner_slots = new LlvmSlotsLowering (artifact, types, functions, cleanup_correspondence, cleanup_functions, classes);
	}

	~LlvmFunctionLowering () {
		CApi.dispose_builder (builder);
	}

	private void retain_value(CApi.ValueRef instruction, CApi.Opcode operation, CApi.TypeRef type, CApi.ValueRef[] inputs, string purpose, int member = -1) {
		if ((void*) CApi.is_instruction (instruction) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (instruction, operation, type, inputs, purpose, member));
		}
	}

	private CApi.ValueRef constructor_stack_place(CApi.ValueRef index) throws LlvmError {
		CApi.ValueRef[] indices = {
			CApi.const_null (types.scalar (NativeScalarType.I32)), index
		};
		return CApi.build_gep (builder, unwind_stack_type, unwind_stack, indices, indices.length, "constructor.owner.slot");
	}

	private void constructor_acquired(SsaInstruction source, LlvmBlockState state) throws LlvmError {
		if (unwind_recipe == null || unwind_recipe.fields.length == 0) {
			return;
		}
		SsaIndirectFieldPlace? place = null;
		var record = source as SsaRecordFieldCommit;
		if (record != null && record.initializes) {
			place = record.destination;
		}
		var buffer = source as SsaBufferWriteInstruction;
		if (buffer != null && buffer.initializes) {
			place = buffer.place.field;
		}
		var slots = source as SsaSlotsEffect;
		if (slots != null && slots.action == SsaSlotsAction.INITIALIZE) {
			place = slots.store;
		}
		var initialize = source as SsaInitializeInstruction;
		if (initialize != null) {
			place = initialize.target as SsaIndirectFieldPlace;
		}
		if (place == null || place.pointer != unwind_constructor.receiver) {
			return;
		}
		bool has_owner = false;
		foreach (var recipe in unwind_recipe.fields) {
			has_owner |= recipe.field == place.field;
		}
		if (!has_owner) {
			return;
		}
		var word = types.scalar (NativeScalarType.I32);
		var count = CApi.build_load (builder, word, unwind_count, "constructor.owner.count");
		scalars.guard_slice_condition (CApi.build_icmp (builder, CApi.IntPredicate.UGE, count, CApi.const_int (word, unwind_recipe.fields.length, 0), "constructor.owner.limit"), "constructor.owner.stack", state);
		var ordinal = CApi.const_int (word, place.field.ordinal, 0);
		CApi.build_store (builder, ordinal, constructor_stack_place (count));
		CApi.build_store (builder, CApi.build_add (builder, count, CApi.const_int (word, 1, 0), "constructor.owner.push"), unwind_count);
	}

	private void constructor_drop_field(SsaConstructorUnwindField recipe, LlvmBlockState state) throws LlvmError, NativeAbiError {
		var field = recipe.field;
		var place = new SsaIndirectFieldPlace (field.span, unwind_constructor.receiver, field);
		if (field.semantic_type is OwnerSlotsType) {
			owner_slots.invoke (builder, field, "drop", new CApi.ValueRef[] { memory_address (place, "constructor.slots", state) }, "");
			return;
		}
		if (recipe.shape != null) {
			lower_record_field (place, recipe.shape, null, false, state);
			return;
		}
		var address = memory_address (place, "constructor.field", state);
		var cleanup = recipe.cleanup;
		if (field.text_snapshot || cleanup != null && cleanup.is_buffer) {
			var carrier = field.text_snapshot ? types.text_descriptor () : types.buffer_carrier ();
			var descriptor = CApi.build_load (builder, carrier, address, "constructor.owned.buffer");
			buffer_allocator.deallocate_buffer (CApi.build_extract_value (builder, descriptor, 0, "constructor.owned.base"), "constructor.owned.buffer", state, field.text_snapshot ? null : LlvmBufferAllocation.buffer_origin (field.owned_cleanup.buffer_type));
			return;
		}
		if (cleanup == null) {
			throw new LlvmError.LOWERING ("constructor field retirement lost exact cleanup");
		}
		var pointer = CApi.build_load (builder, types.scalar (NativeScalarType.PTR), address, "constructor.owned.pointer");
		if (cleanup.closure_type != null) {
			closure_lowering ().release (pointer, cleanup, state);
			return;
		}
		if (cleanup.shared_type != null || cleanup.is_object && ((ClassType) cleanup.object_class.semantic_type).intrinsically_shared) {
			shared_lowering ().release (pointer, cleanup, state);
			return;
		}
		var live = append_block ("constructor.field.live");
		var done = append_block ("constructor.field.retired");
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, pointer, CApi.const_null (types.scalar (NativeScalarType.PTR)), "constructor.field.empty"), done, live);
		CApi.position_builder_at_end (builder, live);
		state.end = live;
		if (cleanup.is_object) {
			classes.release_owned (builder, function.value, buffer_allocator, cleanup.object_class, pointer, state, "constructor.owned.field");
		} else {
			var physical = cleanup_correspondence.lookup (cleanup);
			var callee = physical == null ? null : cleanup_functions.lookup (physical);
			if (callee == null) {
				throw new LlvmError.LOWERING ("constructor Resource lost its original C cleanup");
			}
			var arguments = new CApi.ValueRef[] {
				pointer
			};
			var call = CApi.build_call (builder, callee.type, callee.value, arguments, 1, "");
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			callee.calls.add ((void*) call);
			artifact.class_calls.add (new LlvmClassCallBinding (call, callee.value, callee.type, arguments, CApi.CallConv.C, "constructor exact Resource compensation"));
		}
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
	}

	private void constructor_abort(SsaConstructorAbort abort, LlvmBlockState state) throws LlvmError, NativeAbiError {
		if (unwind_recipe == null || function.constructor_unwind == null || unwind_constructor == null || abort.receiver != unwind_constructor.receiver || function.constructor_unwind.field_count != abort.fields.length) {
			throw new LlvmError.LOWERING ("constructor abort lost exact native unwind authority");
		}
		foreach (var property in abort.lazy_properties) {
			var cache = functions.lookup (property.getter).lazy_cache;
			var cleanup = property.factory.owned_cleanup;
			LlvmLazyProperties.retire (artifact, types, structs, builder, function.value, unwind_constructor.declaring_class, cache, value (abort.receiver), cleanup.destructor == null ? null : functions.lookup (cleanup.destructor), buffer_allocator, state, "constructor.lazy", classes, cleanup.object_class);
		}
		if (abort.fields.length == 0) {
			return;
		}
		var word = types.scalar (NativeScalarType.I32);
		var loop = append_block ("constructor.unwind.next");
		var dispatch = append_block ("constructor.unwind.dispatch");
		var invalid = append_block ("constructor.unwind.invalid");
		var done = append_block ("constructor.unwind.done");
		CApi.build_br (builder, loop);
		CApi.position_builder_at_end (builder, loop);
		state.end = loop;
		var count = CApi.build_load (builder, word, unwind_count, "constructor.unwind.count");
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, count, CApi.const_null (word), "constructor.unwind.empty"), done, dispatch);
		CApi.position_builder_at_end (builder, dispatch);
		state.end = dispatch;
		var index = CApi.build_sub (builder, count, CApi.const_int (word, 1, 0), "constructor.owner.pop");
		CApi.build_store (builder, index, unwind_count);
		var ordinal = CApi.build_load (builder, word, constructor_stack_place (index), "constructor.owner.ordinal");
		var selected = CApi.build_switch (builder, ordinal, invalid, abort.fields.length);
		foreach (var recipe in abort.fields) {
			var active = append_block ("constructor.unwind.field%d".printf (recipe.field.ordinal));
			CApi.add_case (selected, CApi.const_int (word, recipe.field.ordinal, 0), active);
			CApi.position_builder_at_end (builder, active);
			state.end = active;
			constructor_drop_field (recipe, state);
			CApi.build_br (builder, loop);
		}
		CApi.position_builder_at_end (builder, invalid);
		state.end = invalid;
		scalars.guard_slice_condition (CApi.const_int (types.scalar (NativeScalarType.B1), 1, 0), "constructor.unwind.ordinal", state);
		CApi.build_unreachable (builder);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
	}

	private CApi.ValueRef class_field_address(CApi.TypeRef layout, CApi.ValueRef receiver, uint field, string name, SsaStructField? declaration = null) throws LlvmError {
		bool restricted = declaration != null && declaration.is_private;
		if (restricted && declaration.containing_type.semantic_type != lexical_field_owner) {
			throw new LlvmError.INVALID_INPUT ("private field address requires its exact lexical declaring Class");
		}
		var address = CApi.build_struct_gep (builder, layout, receiver, field, name);
		artifact.class_addresses.add (new LlvmClassAddressBinding (address, receiver, layout, field, true, restricted ? function.value : (CApi.ValueRef) null, restricted ? CApi.insert_block (builder) : (CApi.BasicBlockRef) null));
		return address;
	}

	private CApi.ValueRef success_read(CApi.TypeRef type, CApi.ValueRef slot, string name) {
		var result = CApi.build_load (builder, type, slot, name);
		retain_value (result, CApi.Opcode.LOAD, type, new CApi.ValueRef[] { slot }, "guarded private success storage");
		return result;
	}

	private void success_write(CApi.ValueRef value) {
		var stored = CApi.build_store (builder, value, exception_success_slot);
		retain_value (stored, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { value, exception_success_slot }, "complete private success publication");
	}

	private CApi.ValueRef snapshot_text(CApi.ValueRef input, string name, LlvmBlockState state) throws LlvmError {
		var length = CApi.build_extract_value (builder, input, 1, name + ".snapshot.length");
		var incoming = CApi.build_extract_value (builder, input, 0, name + ".snapshot.input");
		retain_value (length, CApi.Opcode.EXTRACT_VALUE, types.scalar (NativeScalarType.I32), new CApi.ValueRef[] { input }, "snapshot source count", 1);
		retain_value (incoming, CApi.Opcode.EXTRACT_VALUE, types.scalar (NativeScalarType.PTR), new CApi.ValueRef[] { input }, "snapshot source backing", 0);
		var pointer = buffer_allocator.allocate (length, types.scalar (NativeScalarType.U8), name + ".snapshot", state);
		var size_type = CApi.int_type_in_context (artifact.context, 64);
		var pointer_type = types.scalar (NativeScalarType.PTR);
		string intrinsic_name = "llvm.memcpy";
		uint identity = CApi.lookup_intrinsic_id (intrinsic_name, intrinsic_name.length);
		CApi.TypeRef[] overloads = {
			pointer_type, pointer_type, size_type
		};
		var target = CApi.get_intrinsic_declaration (artifact.module, identity, overloads, overloads.length);
		var signature = CApi.intrinsic_get_type (artifact.context, identity, overloads, overloads.length);
		CApi.ValueRef[] arguments = {
			pointer, incoming, CApi.build_zext (builder, length, size_type, name + ".snapshot.bytes"), CApi.const_null (types.scalar (NativeScalarType.B1))
		};
		var copy = CApi.build_call (builder, signature, target, arguments, arguments.length, "");
		artifact.class_calls.add (new LlvmClassCallBinding (copy, target, signature, arguments, CApi.CallConv.C, "snapshot exact source/backing/count copy"));
		retain_value (arguments[2], CApi.Opcode.ZEXT, size_type, new CApi.ValueRef[] { length }, "snapshot byte extent");
		var result = CApi.build_insert_value (builder, CApi.const_null (types.text_descriptor ()), pointer, 0, name + ".snapshot.base");
		retain_value (result, CApi.Opcode.INSERT_VALUE, types.text_descriptor (), new CApi.ValueRef[] { CApi.const_null (types.text_descriptor ()), pointer }, "snapshot new backing", 0);
		var snapshot = CApi.build_insert_value (builder, result, length, 1, name + ".snapshot.text");
		retain_value (snapshot, CApi.Opcode.INSERT_VALUE, types.text_descriptor (), new CApi.ValueRef[] { result, length }, "snapshot paired count", 1);
		return snapshot;
	}

	private CApi.ValueRef reserve_c_record_slot(LlvmCTypeMapper mapper, CAbiRecordPlan record, string name) throws LlvmError {
		var layout = mapper.record_type (record);
		var slot = CApi.build_alloca (builder, layout, name);
		CApi.set_alignment (slot, record.alignment);
		artifact.c_record_slots.add (new LlvmCRecordStackSlot (slot, function.value, layout, record.alignment));
		return slot;
	}

	private void bind(SsaValue source, CApi.ValueRef value) throws LlvmError, NativeAbiError {
		if (async_exception_slots.contains (source)) {
			CApi.build_store (builder, value, (CApi.ValueRef) async_exception_slots.lookup (source));
			return;
		}
		if ((void*) CApi.type_of (value) != (void*) types.value_type (source.semantic_type)) {
			throw new LlvmError.LOWERING ("internal LLVM lowering error: SSA value physical type mismatch");
		}
		values.insert (source, (void*) value);
		if (function.async_frame != null && source is SsaDefinition) {
			function.async_frame.write (builder, ((SsaDefinition) source).ordinal, value);
		}
		if (buffer_exchanges.size () > 0 && source is SsaDefinition && (source.semantic_type is ClassType || source.semantic_type is ReceiverType)) {
			buffer_receivers.insert (source, new LlvmBufferReceiverBinding (function_ordinal, (SsaDefinition) source, value));
		}
	}

	private CApi.ValueRef value(SsaValue source) throws LlvmError, NativeAbiError {
		if (source is SsaCallbackView) {
			var view = (SsaCallbackView) source;
			return callbacks ().from_closure (builder, (CallbackType) view.semantic_type, value (view.closure));
		}
		if (source is SsaFunctionAddress) {
			var address = (SsaFunctionAddress) source;
			var target = functions.lookup (address.target);
			if (target == null) {
				throw new LlvmError.LOWERING ("function address lost exact native declaration");
			}
			return (source.semantic_type is CallbackType) ? callbacks ().address ((CallbackType) source.semantic_type, target, address.target.ordinal) : target.value;
		}
		if (async_exception_slots.contains (source)) {
			return CApi.build_load (builder, types.scalar (NativeScalarType.PTR), (CApi.ValueRef) async_exception_slots.lookup (source), "virtual.exception");
		}
		if (source is SsaTaskAbsent) {
			return CApi.const_null (types.scalar (NativeScalarType.PTR));
		}
		if (function.async_frame != null && source is SsaDefinition) {
			return function.async_frame.read (builder, ((SsaDefinition) source).ordinal, types.value_type (source.semantic_type));
		}
		if (!values.contains (source)) {
			if (source is SsaEnumArgument) {
				bind (source, enum_address (((SsaEnumArgument) source).source));
				return (CApi.ValueRef) values.lookup (source);
			}
			var integer = source as SsaIntegerConstant;
			var boolean = source as SsaBooleanConstant;
			if (source is SsaResultStorageReceiverValue) {
				bind (source, value (((SsaResultStorageReceiverValue) source).storage));
			} else if (source is SsaNullPointerConstant) {
				bind (source, CApi.const_pointer_null (types.scalar (NativeScalarType.PTR)));
			} else if (source is SsaTextConstant) {
				bind (source, text.literal (((SsaTextConstant) source).payload));
			} else if (source is SsaFloatConstant) {
				bind (source, scalars.floating (((SsaFloatConstant) source).value));
			} else if (integer != null) {
				bind (source, scalars.integer (integer.value));
			} else if (boolean != null) {
				bind (source, CApi.const_int (types.scalar (NativeScalarType.B1), boolean.literal == BooleanLiteral.TRUE ? 1 : 0, 0));
			} else {
				throw new LlvmError.LOWERING ("internal LLVM lowering error: SSA value has no mapped definition");
			}
		}
		return (CApi.ValueRef) values.lookup (source);
	}

	// Backend-only realization of the shared clamp-to-destination interval.
	// Bounds are representable in the wider source type; compare according to
	// source signedness before narrowing. No overflowing arithmetic is needed.
	private CApi.ValueRef saturating_narrow(CApi.ValueRef operand, VectorType source, IntegerType destination, string name) throws LlvmError, NativeAbiError {
		var element = (IntegerType) source.element_type;
		var clamped = operand;
		if (element.minimum < destination.minimum) {
			var minimum = dsp_bound (source, destination.minimum);
			var below = CApi.build_icmp (builder, element.is_signed ? CApi.IntPredicate.SLT : CApi.IntPredicate.ULT, clamped, minimum, name + ".below");
			clamped = CApi.build_select (builder, below, minimum, clamped, name + ".min");
		}
		if (element.maximum > destination.maximum) {
			var maximum = dsp_bound (source, (int64) destination.maximum);
			var above = CApi.build_icmp (builder, element.is_signed ? CApi.IntPredicate.SGT : CApi.IntPredicate.UGT, clamped, maximum, name + ".above");
			clamped = CApi.build_select (builder, above, maximum, clamped, name + ".max");
		}
		return CApi.build_trunc (builder, clamped, CApi.vector_type (types.value_type (destination), source.lane_count), name);
	}

	private CApi.ValueRef dsp_bound(VectorType source, int64 number) throws LlvmError, NativeAbiError {
		var scalar = scalars.integer (AstraIntegerValue.from_int64 ((IntegerType) source.element_type, number));
		var lanes = new CApi.ValueRef[source.lane_count];
		for (int i = 0; i < lanes.length; i++) {
			lanes[i] = scalar;
		}
		return CApi.const_vector (lanes, lanes.length);
	}

	private CApi.ValueRef lower_vector_dot(SsaVectorDotInstruction dot, string name, LlvmBlockState state) throws LlvmError, NativeAbiError {
		var source = (VectorType) dot.source_type;
		var scalar = types.value_type (dot.destination_type);
		var first = value (dot.first);
		var second = value (dot.second);
		bool integer = dot.dot_kind.is_integer ();
		if (integer) {
			var element = (IntegerType) source.element_type;
			if (element.bit_width < ((IntegerType) dot.destination_type).bit_width) {
				// This physical type may exceed Astra's source shape limit.
				// Source signedness, independently of D, controls extension.
				var wide = CApi.vector_type (scalar, source.lane_count);
				first = element.is_signed ? CApi.build_sext (builder, first, wide, name + ".a") : CApi.build_zext (builder, first, wide, name + ".a");
				second = element.is_signed ? CApi.build_sext (builder, second, wide, name + ".b") : CApi.build_zext (builder, second, wide, name + ".b");
			}
		}
		// Ordinary operations carry no overflow or fast-math flags. F32
		// products round before the strict ascending scalar addition chain.
		var products = integer ? CApi.build_mul (builder, first, second, name + ".products") : scalars.binary (BinaryOperator.MULTIPLY, dot.source_type, first, second, name + ".products", state);
		var acc = dot.accumulator == null ? CApi.const_null(scalar) : value (dot.accumulator);
		for (int i = 0; i < source.lane_count; i++) {
			var lane = CApi.build_extract_element (builder, products, CApi.const_int (types.scalar (NativeScalarType.I32), i, 0), name + ".lane%d".printf (i));
			string step = i == source.lane_count - 1 ? name : name + ".acc%d".printf (i);
			acc = integer ? CApi.build_add (builder, acc, lane, step) : scalars.binary (BinaryOperator.ADD, dot.destination_type, acc, lane, step, state);
		}
		return acc;
	}

	private void guard_volatile_alignment(CApi.ValueRef pointer, uint alignment, string name, LlvmBlockState state) throws LlvmError {
		var integer = types.scalar (NativeScalarType.U64);
		var address = CApi.build_ptr_to_int (builder, pointer, integer, name + ".address");
		var low = CApi.build_and (builder, address, CApi.const_int (integer, alignment - 1, 0), name + ".alignment");
		var invalid = CApi.build_icmp (builder, CApi.IntPredicate.NE, low, CApi.const_null (integer), name + ".misaligned");
		scalars.guard_slice_condition (invalid, name + ".alignment", state);
	}

	private CApi.ValueRef lower_dsp(SsaDspInstruction dsp, string name) throws LlvmError, NativeAbiError {
		var kind = dsp.primitive_kind;
		var first = value (dsp.first);
		if (kind.is_saturation ()) {
			var element = IntegerConversion.element_type (dsp.source_type);
			string intrinsic = "llvm.%s%s.sat".printf (element.is_signed ? "s" : "u", kind == DspPrimitiveKind.SAT_ADD ? "add" : "sub");
			uint id = CApi.lookup_intrinsic_id (intrinsic, intrinsic.length);
			assert (id != 0);
			CApi.TypeRef[] overloads = {
				types.value_type (dsp.source_type)
			};
			var declaration = CApi.get_intrinsic_declaration (artifact.module, id, overloads, 1);
			var signature = CApi.intrinsic_get_type (artifact.context, id, overloads, 1);
			CApi.ValueRef[] arguments = {
				first, value (dsp.second)
			};
			var call = CApi.build_call (builder, signature, declaration, arguments, 2, name);
			artifact.saturations.add (new LlvmSaturationBinding (call, declaration, signature, arguments[0], arguments[1], id));
			return call;
		}
		var source = (VectorType) dsp.source_type;
		var output = (VectorType) dsp.destination_type;
		var indices = new CApi.ValueRef[output.lane_count];
		var index_type = types.scalar (NativeScalarType.I32);
		if (kind.is_widen ()) {
			int start = kind == DspPrimitiveKind.WIDEN_LOW ? 0 : source.lane_count / 2;
			for (int i = 0; i < indices.length; i++) {
				indices[i] = CApi.const_int (index_type, start + i, 0);
			}
			var half = CApi.build_shuffle_vector (builder, first, first, CApi.const_vector (indices, indices.length), name + ".half");
			// ICONV-1: extension follows SOURCE mathematical interpretation.
			return ((IntegerType) source.element_type).is_signed ? CApi.build_sext (builder, half, types.value_type (output), name) : CApi.build_zext (builder, half, types.value_type (output), name);
		}
		var second = value (dsp.second);
		if (kind.is_pack ()) {
			var narrow_type = CApi.vector_type (types.value_type (dsp.destination_element), source.lane_count);
			first = kind == DspPrimitiveKind.PACK_SAT ? saturating_narrow (first, source, dsp.destination_element, name + ".first") : CApi.build_trunc (builder, first, narrow_type, name + ".first");
			second = kind == DspPrimitiveKind.PACK_SAT ? saturating_narrow (second, source, dsp.destination_element, name + ".second") : CApi.build_trunc (builder, second, narrow_type, name + ".second");
			for (int i = 0; i < indices.length; i++) {
				indices[i] = CApi.const_int (index_type, i, 0);
			}
		} else {
			int start = kind == DspPrimitiveKind.INTERLEAVE_LOW ? 0 : source.lane_count / 2;
			for (int i = 0; i < indices.length; i++) {
				indices[i] = CApi.const_int (index_type, start + i / 2 + (i % 2) * source.lane_count, 0);
			}
		}
		// Every selector names a defined input lane, including f32 and masks.
		return CApi.build_shuffle_vector (builder, first, second, CApi.const_vector (indices, indices.length), name);
	}

	private CApi.BasicBlockRef append_block(string name) {
		return CApi.append_basic_block_in_context (artifact.context, function.value, name);
	}

	private void create_block(SsaBlock block) {
		blocks.insert (block, new LlvmBlockState (append_block ("b%d".printf (block.ordinal))));
	}

	internal void lower(SsaFunction source) throws LlvmError, NativeAbiError {
		foreach (var plan in scoped_plans) {
			if (!plan.valid ()) {
				throw new LlvmError.LOWERING ("scoped backing lost its original native plan");
			}
			var binding = new LlvmScopedBackingBinding (function.value, plan.storage_ordinal, (int) plan.retirements.length / 2);
			artifact.bind_scoped_backing (binding);
			scoped_factories.insert (plan.result_ordinal, binding);
			for (int e = 0; e < plan.retirements.length; e += 2) {
				var cleanup = source.blocks[plan.retirements[e]].instructions[plan.retirements[e + 1]] as SsaCleanupInstruction;
				if (cleanup == null || scoped_retirements.contains (cleanup)) {
					throw new LlvmError.LOWERING ("scoped backing lost exact unique lexical cleanup sites");
				}
				scoped_retirements.insert (cleanup, binding);
			}
		}
		if (artifact.semantic_optimizations) {
			foreach (var root in source.stack_objects) {
				promoted_objects.insert (root, true);
			}
		}
		if (artifact.semantic_optimizations) {
			foreach (var plan in source.shared_elisions) {
				elided_copies.insert (plan.acquisition, true);
				elided_releases.insert (plan.cleanup, true);
			}
		}
		scalars.floating_policy = source.floating_policy;
		if (artifact.debug_info != null) {
			debug_scope = artifact.debug_info.function_scope (source, function.value, structs, artifact);
		}
		// Abstract interface placeholders have no executable source body.
		// Attribute their generated instructions to the operation declaration.
		var interface_method = source as SsaMethod;
		bool declaration_location = source.utf8_factory || interface_method != null && interface_method.declaring_type.semantic_type is ClassType && ((ClassType) interface_method.declaring_type.semantic_type).is_interface;
		function_ordinal = source.ordinal;
		unwind_constructor = source as SsaConstructor;
		if (function.constructor_unwind != null) {
			foreach (var block in source.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction is SsaConstructorAbort) {
						unwind_recipe = (SsaConstructorAbort) instruction;
					}
				}
			}
		}
		lexical_field_owner = source.implicit_receiver == null ? null : source.implicit_receiver.contract.instance_type;
		async_entry = (CApi.BasicBlockRef) (void*) null;
		async_heap_owner_count = source.heap_owners.length;
		if (function.async_frame != null) {
			async_entry = append_block ("task.dispatch");
			foreach (var candidate in functions.get_keys ()) {
				var constructor = candidate as SsaConstructor;
				if (constructor != null && constructor.declaring_class.semantic_type == source.async_body.runtime.error_type) {
					async_error_class = constructor.declaring_class;
				}
			}
			if (async_error_class == null) {
				throw new LlvmError.LOWERING ("nominated runtime exception has no exact class/constructor identity");
			}
		}
		foreach (var block in source.blocks) {
			for (int i = 0; i < block.instructions.length; i++) {
				var exchange = block.instructions[i] as SsaBufferExchangeInstruction;
				if (exchange != null) {
					buffer_exchanges.insert (exchange, LlvmBufferExchangePlan.build (source, block, i));
				}
			}
		}
		// LLVM's first physical block is its entry, independent of ordinals.
		create_block (source.entry);
		for (int b = 0; b < source.blocks.length; b++) {
			if (source.blocks[b] != source.entry) {
				create_block (source.blocks[b]);
			}
		}
		for (int b = 0; b < source.blocks.length; b++) {
			var block = source.blocks[b];
			CApi.position_builder_at_end (builder, blocks.lookup (block).primary);
			for (int p = 0; p < block.parameters.length; p++) {
				if (function.async_frame != null) {
					continue;
				}
				var parameter = block.parameters[p];
				bind (parameter, CApi.build_phi (builder, types.value_type (parameter.semantic_type), "v%d".printf (parameter.ordinal)));
			}
		}
		if (function.async_frame != null) {
			CApi.position_builder_at_end (builder, async_entry);
			foreach (var block in source.blocks) {
				foreach (var instruction in block.instructions) {
					var call = instruction as SsaCallInstruction;
					if (!(call is SsaTaskCreate) && call != null && call.exception_result != null && functions.lookup (call.target).signature.has_exception_success_slot) {
						exception_call_slots.insert (call, (void*) CApi.build_alloca (builder, types.success_result_type (functions.lookup (call.target).signature), "turn.success.%d".printf (call.exception_result.ordinal)));
					}
				}
			}
		}
		if (unwind_recipe != null) {
			var plan = function.constructor_unwind;
			if (unwind_constructor == null || plan == null || plan.class_ordinal != unwind_constructor.declaring_class.ordinal || plan.field_count != unwind_recipe.fields.length || plan.lazy_count != unwind_recipe.lazy_properties.length) {
				throw new LlvmError.LOWERING ("constructor unwind lost exact native field/cache inventory");
			}
			for (int f = 0; f < plan.field_count; f++) {
				if (plan.field (f) != unwind_recipe.fields[f].field.ordinal) {
					throw new LlvmError.LOWERING ("constructor unwind field differs from native declaration");
				}
			}
			for (int p = 0; p < plan.lazy_count; p++) {
				if (plan.lazy_property (p) != unwind_recipe.lazy_properties[p].ordinal) {
					throw new LlvmError.LOWERING ("constructor unwind cache differs from native declaration");
				}
			}
		}
		if (unwind_recipe != null && unwind_recipe.fields.length != 0) {
			CApi.position_builder_at_end (builder, blocks.lookup (source.entry).primary);
			var word = types.scalar (NativeScalarType.I32);
			unwind_stack_type = CApi.array_type (word, unwind_recipe.fields.length);
			unwind_stack = CApi.build_alloca (builder, unwind_stack_type, "constructor.acquisition.order");
			unwind_count = CApi.build_alloca (builder, word, "constructor.acquisition.count");
			var empty = CApi.const_null (word);
			var store = CApi.build_store (builder, empty, unwind_count);
			retain_value (store, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { empty, unwind_count }, "empty constructor owner stack");
		}
		// C MEMORY staging slots belong to the physical function entry,
		// including async dispatch, and are reused on every loop iteration.
		CApi.position_builder_at_end (builder, function.async_frame == null ? blocks.lookup (source.entry).primary : async_entry);
		var c_record_types = new LlvmCTypeMapper (artifact.context);
		foreach (var block in source.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaCCallInstruction;
				if (call == null) {
					continue;
				}
				var signature = c_correspondence.lookup (call.target).signature;
				var slots = new GenericArray<void*> ();
				slots.add (signature.result != null && signature.result.record != null && signature.result.record.memory ? (void*) reserve_c_record_slot (c_record_types, signature.result.record, "c.record.result") : null);
				foreach (var parameter in signature.parameters) {
					slots.add (parameter.record != null && parameter.record.memory ? (void*) reserve_c_record_slot (c_record_types, parameter.record, "c.record.byval") : null);
				}
				c_record_slots.insert (call, slots);
			}
		}
		// Reserve all aggregate storage in the primary entry before user
		// operations. Initialization remains at its source instruction point.
		CApi.position_builder_at_end (builder, blocks.lookup (source.entry).primary);
		if (function.async_frame != null) {
			function.async_frame.begin (builder, async_entry, blocks.lookup (source.entry).primary);
			if (debug_scope != null) {
				// The dispatch entry executes on every resume. Bind captured Source
				// parameters to their actual persistent fields, never stale registers.
				CApi.position_builder_before (builder, CApi.block_terminator (async_entry));
				for (int p = 0; p < source.parameters.length; p++) {
					uint original;
					if (!LlvmDebugInfo.scalar_parameter (source, p, out original)) {
						continue;
					}
					var type = artifact.debug_info.value_type (source.parameters[p].semantic_type, structs, artifact);
					if ((void*) type == null) {
						continue;
					}
					uint index = function.async_frame.debug_value_index (source.parameters[p].ordinal);
					artifact.debug_info.frame_parameter (debug_scope, source.parameters[p], original, function.async_frame.debug_environment (), function.async_frame.frame_type, index, async_entry, type, artifact);
				}
			}
			CApi.position_builder_at_end (builder, blocks.lookup (source.entry).primary);
		}
		foreach (var block in source.blocks) {
			foreach (var instruction in block.instructions) {
				var operation = instruction as SsaAsyncOperation;
				if (function.async_frame == null && operation != null && operation.exception != null) {
					async_exception_slots.insert (operation.exception, (void*) CApi.build_alloca (builder, types.scalar (NativeScalarType.PTR), "virtual.exception.slot"));
				}
			}
		}
		int component = 0;
		if (function.async_frame == null && function.signature.sum_result != null) {
			sum_result = CApi.get_param (function.value, component++);
			CApi.set_value_name (sum_result, "sum.result.storage", 18);
		}
		foreach (var slot in source.enum_slots) {
			if (function.async_frame != null) {
				continue;
			}
			var layout = sum_registry.lookup (slot.definition.semantic_type.identity);
			var address = CApi.build_alloca (builder, layout.carrier, "sum.slot%d".printf (slot.ordinal));
			CApi.set_alignment (address, layout.alignment);
			enum_storage.insert (slot, (void*) address);
			if (layout.plan.owning && slot.inspection_root == null) {
				var flag = CApi.build_alloca (builder, CApi.int1_type_in_context (artifact.context), "sum.live%d".printf (slot.ordinal));
				CApi.build_store (builder, CApi.const_int (CApi.int1_type_in_context (artifact.context), 0, 0), flag);
				enum_liveness.insert (slot, (void*) flag);
			}
		}
		if (source.result_storage != null) {
			var candidate = CApi.get_param (function.value, component++);
			CApi.set_value_name (candidate, "result.storage", 14);
			bind (source.result_storage, candidate);
		}
		if (source.implicit_receiver != null) {
			var receiver = CApi.get_param (function.value, component++);
			CApi.set_value_name (receiver, "this", 4);
			bind (source.implicit_receiver, receiver);
		}
		if (function.async_frame == null && function.signature.has_exception_success_slot) {
			exception_success_slot = CApi.get_param (function.value, component++);
			CApi.set_value_name (exception_success_slot, "success.storage", 15);
		}
		foreach (var block in source.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaCallInstruction;
				if (function.async_frame == null && call != null && call.exception_result != null && functions.lookup (call.target).signature.has_exception_success_slot) {
					exception_call_slots.insert (call, (void*) CApi.build_alloca (builder, types.success_result_type (functions.lookup (call.target).signature), "exception.success.%d".printf (call.exception_result.ordinal)));
				}
			}
		}
		foreach (var block in source.blocks) {
			foreach (var instruction in block.instructions) {
				var call = instruction as SsaClosureCall;
				if (call != null && ((ClosureHandleType) call.callee.semantic_type).throws_type != null && ((ClosureHandleType) call.callee.semantic_type).result_type.kind != TypeKind.VOID) {
					checked_closure_slots.insert (call, (void*) CApi.build_alloca (builder, types.callable_result_type ((ClosureHandleType) call.callee.semantic_type), "closure.success.%d".printf (call.result.ordinal)));
				}
			}
		}

		for (int p = 0; p < source.parameters.length; p++) {
			if (function.async_frame != null) {
				continue;
			}
			var parameter = CApi.get_param (function.value, component++);
			string name = "p%d".printf (p);
			if (function.signature.parameters[p].abi_type is NativeTextType || function.signature.parameters[p].abi_type is NativeSliceType) {
				var length = CApi.get_param (function.value, component++);
				CApi.set_value_name (parameter, name + ".base", (name + ".base").length);
				CApi.set_value_name (length, name + ".length", (name + ".length").length);
				var view = CApi.build_insert_value (builder, CApi.const_null (types.value_type (source.parameters[p].semantic_type)), parameter, 0, name + ".with.base");
				bind (source.parameters[p], CApi.build_insert_value (builder, view, length, 1, name));
			} else {
				CApi.set_value_name (parameter, name, name.length);
				bind (source.parameters[p], parameter);
				uint original_parameter = 0;
				if (debug_scope != null && LlvmDebugInfo.scalar_parameter (source, p, out original_parameter)) {
					artifact.debug_info.parameter (debug_scope, source.parameters[p], original_parameter, parameter, builder, artifact.debug_info.value_type (source.parameters[p].semantic_type, structs, artifact));
				}
			}
		}
		foreach (var object in source.object_storage) {
			if (object.heap_allocated && !promoted_objects.contains (object)) {
				continue;
			}
			var pointer = CApi.build_alloca (builder, structs.lookup (object.object_class), (promoted_objects.contains (object) ? "stack.object%d" : "object%d").printf (object.ordinal));
			if (object.object_class.allocation_policy != null) {
				if (artifact.class_target == null) {
					artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
				}
				CApi.set_alignment (pointer, uint.max (object.object_class.allocation_policy.alignment, CApi.abi_alignment_of_type (artifact.class_target.enum_target_data (artifact), structs.lookup (object.object_class))));
			}
			if (object.object_class.allocation_policy != null) {
				artifact.class_values.add (new LlvmClassValueBinding (pointer, CApi.Opcode.ALLOCA, CApi.type_of (pointer), new CApi.ValueRef[] { CApi.operand (pointer, 0) }, "policy-aligned caller storage", -1, -1, (int) CApi.get_alignment (pointer)));
			}
			object_storage.insert (object, (void*) pointer);
		}
		foreach (var block in source.blocks) {
			foreach (var instruction in block.instructions) {
				var read = instruction as SsaBufferReadInstruction;
				if (read != null && read.place.storage != null) {
					async_buffer_reads.insert (read.pair, read.place.storage);
				}
			}
		}
		foreach (var slot in source.buffer_storage) {
			if (function.async_frame != null) {
				continue;
			}
			var address = CApi.build_alloca (builder, types.buffer_carrier (), "buffer%d".printf (slot.ordinal));
			buffer_storage.insert (slot, (void*) address);
			if (buffer_exchanges.size () > 0) {
				buffer_origins.insert (slot, new LlvmBufferLocalBinding (source.ordinal, slot, address));
			}
		}
		foreach (var object in source.storage) {
			if (function.async_frame != null) {
				continue;
			}
			var pointer = CApi.build_alloca (builder, (object.structure == null ? types.storage_type (object.semantic_type) : structs.lookup (object.structure)), "storage%d".printf (object.ordinal));
			storage.insert (object, (void*) pointer);
			if (debug_scope != null) {
				var aggregate = object.structure == null ? (CApi.MetadataRef) null : artifact.debug_info.record_type (object.structure, structs, artifact);
				artifact.debug_info.local (debug_scope, object, pointer, CApi.insert_block (builder), aggregate);
			}
		}
		policy_receiver = source.implicit_receiver;
		var policy_type = policy_receiver == null ? null : policy_receiver.contract.instance_type as ClassType;
		monitor_guard = (CApi.ValueRef) null;
		if (policy_type != null && !(source is SsaConstructor)) {
			var pointer = types.scalar (NativeScalarType.PTR);
			var nothing = CApi.void_type_in_context (artifact.context);
			if (policy_type.thread_bound) {
				var identity = LlvmConcurrencyRuntime.member (artifact, builder, value (policy_receiver), 5, true);
				LlvmConcurrencyRuntime.call (artifact, builder, "astra_concurrency_thread_check", nothing, new CApi.TypeRef[] { types.scalar (NativeScalarType.U64) }, new CApi.ValueRef[] { identity });
			}
			if (policy_type.monitored && !(source is SsaLifecycle)) {
				monitor_guard = LlvmConcurrencyRuntime.member (artifact, builder, value (policy_receiver), 4);
				LlvmConcurrencyRuntime.call (artifact, builder, "astra_monitor_enter", nothing, new CApi.TypeRef[] { pointer }, new CApi.ValueRef[] { monitor_guard });
			}
		}
		// DFS preorder visits dominators before their uses even when array
		// order does not. All block parameters already have physical values.
		var pending = new GenericArray<SsaBlock> ();
		var visited = new HashTable<SsaBlock, SsaBlock> (direct_hash, direct_equal);
		pending.add (source.entry);
		while (pending.length != 0) {
			var block = pending[pending.length - 1];
			pending.remove_index (pending.length - 1);
			if (visited.contains (block)) {
				continue;
			}
			visited.insert (block, block);
			var state = blocks.lookup (block);
			CApi.position_builder_at_end (builder, state.end);
			for (int i = 0; i < block.instructions.length; i++) {
				// The nominated UTF-8 factory has generated syntax, not a user body.
				// Attribute its implementation to the real bodyless declaration.
				if (debug_scope != null) {
					artifact.debug_info.position (debug_scope, builder, declaration_location ? source.name_span : block.instructions[i].span);
				}
				if (block.instructions[i] is SsaAsyncDelay) {
					if (function.async_frame == null) {
						throw new LlvmError.LOWERING ("async suspension has no exact frame association");
					}
					var delay = (SsaAsyncDelay) block.instructions[i];
					CApi.BasicBlockRef failure;
					var resumed = function.async_frame.suspend (builder, value (delay.ticks), delay.ticks.semantic_type.kind == TypeKind.INT, block.ordinal, i, out failure, delay.payload);
					var joined = append_block ("delay.delivery");
					if (!delay.body.runtime.linux) {
						// Keep the qualified virtual instruction/name emission order exact.
						CApi.position_builder_at_end (builder, failure);
						state.end = failure;
						bind (delay.result, runtime_error (delay.span, state));
						CApi.build_br (builder, joined);
						CApi.position_builder_at_end (builder, resumed);
						bind (delay.result, CApi.const_null (types.scalar (NativeScalarType.PTR)));
						CApi.build_br (builder, joined);
						CApi.position_builder_at_end (builder, joined);
						state.end = joined;
						continue;
					}
					CApi.position_builder_at_end (builder, resumed);
					state.end = resumed;
					var runtime = new LlvmAsyncRuntime (artifact);
					var status = function.async_frame.delay_result (builder, block.ordinal, i);
					var success = append_block ("delay.completion.success");
					var zero = CApi.const_null (runtime.i32);
					var checked_completion = CApi.build_icmp (builder, CApi.IntPredicate.EQ, status, zero, "delay.completion.check");
					artifact.class_values.add (new LlvmClassValueBinding (checked_completion, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { status, zero }, "Linux deferred error is checked after observed retirement", -1, (int) CApi.IntPredicate.EQ));
					var completion_branch = CApi.build_cond_br (builder, checked_completion, success, failure);
					artifact.class_branches.add (new LlvmClassBranchBinding (completion_branch, checked_completion, success, failure));
					CApi.position_builder_at_end (builder, success);
					state.end = success;
					bind (delay.result, CApi.const_null (types.scalar (NativeScalarType.PTR)));
					CApi.build_br (builder, joined);
					CApi.position_builder_at_end (builder, failure);
					state.end = failure;
					bind (delay.result, runtime_error (delay.span, state, delay.payload ? "Linux io_uring payload operation failed" : "Linux io_uring timer operation failed"));
					CApi.build_br (builder, joined);
					CApi.position_builder_at_end (builder, joined);
					state.end = joined;
					continue;
				}
				if (block.instructions[i] is SsaTaskWait) {
					lower_task_wait ((SsaTaskWait) block.instructions[i], block.ordinal, i, state);
					continue;
				}
				instruction (block.instructions[i], state);
				constructor_acquired (block.instructions[i], state);
			}
			if (debug_scope != null) {
				artifact.debug_info.position (debug_scope, builder, declaration_location ? source.name_span : block.terminator.span);
			}
			terminator (block, state);
			var successors = block.terminator.successors ();
			for (int s = successors.length - 1; s >= 0; s--) {
				pending.add (successors[s]);
			}
		}
		if ((void*) monitor_guard != null) {
			for (var block = CApi.first_block (function.value); (void*) block != null; block = CApi.next_block (block)) {
				var returned = CApi.block_terminator (block);
				if ((void*) returned == null || CApi.opcode (returned) != CApi.Opcode.RET) {
					continue;
				}
				CApi.position_builder_before (builder, returned);
				LlvmConcurrencyRuntime.call (artifact, builder, "astra_monitor_leave", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { types.scalar (NativeScalarType.PTR) }, new CApi.ValueRef[] { monitor_guard });
			}
			artifact.concurrency_guards.add (new LlvmSumSequence (function.value, true));
		}
		if (function.async_frame != null) {
			emit_async_destroy (source);
			function.async_frame.seal_effects ();
		}
		if (guarded_c_union) {
			artifact.c_union_guards.add (new LlvmSumSequence (function.value, true));
		}
		if (function.constructor_unwind != null) {
			artifact.constructor_unwinds.add (new LlvmSumSequence (function.value, true));
		}
	}

	private CApi.ValueRef runtime_error(SourceSpan span, LlvmBlockState state, string message_text = "virtual task admission refused", SsaClass? error_class = null) throws LlvmError {
		var owner = error_class ?? async_error_class;
		var constructor = functions.lookup (owner.constructor);
		var pointer = buffer_allocator.allocate (CApi.const_int (types.scalar (NativeScalarType.I32), 1, 0), structs.lookup (owner), "task.admission.error", state, false, null, true);
		classes.initialize (builder, owner, pointer, "task.error");
		var message = text.literal (new Astra.Text.TextBytes (message_text.data));
		CApi.ValueRef[] arguments = {
			pointer, CApi.build_extract_value (builder, message, 0, "error.text"), CApi.build_extract_value (builder, message, 1, "error.length")
		};
		var call = CApi.build_call (builder, constructor.type, constructor.value, arguments, arguments.length, "");
		CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (call, constructor.value, constructor.type, arguments, LlvmLowering.CALL_CONVENTION, "exact nominated ordinary runtime exception construction"));
		classes.stamp_origin (builder, pointer, span);
		return pointer;
	}

	private void lower_async_operation(SsaAsyncOperation operation, LlvmBlockState state) throws LlvmError, NativeAbiError {
		var runtime = new LlvmAsyncRuntime (artifact);
		var pointer = types.scalar (NativeScalarType.PTR);
		var i32 = types.scalar (NativeScalarType.I32);
		var nothing = CApi.void_type_in_context (artifact.context);
		var kind = operation.contract.kind;
		if (operation.exception != null) {
			foreach (var candidate in functions.get_keys ()) {
				var constructor = candidate as SsaConstructor;
				if (constructor != null && constructor.declaring_class.semantic_type == operation.contract.runtime.error_type) {
					async_error_class = constructor.declaring_class;
				}
			}
			if (async_error_class == null) {
				throw new LlvmError.LOWERING ("runtime operation lost exact nominated Error class");
			}
			bind (operation.exception, CApi.const_null (pointer));
		}
		var executor = operation.executor == null ? (CApi.ValueRef) (void*) null : value (operation.executor);
		var task = operation.task == null ? (CApi.ValueRef) (void*) null : value (operation.task);
		var argument = operation.argument == null ? (CApi.ValueRef) (void*) null : value (operation.argument);
		CApi.ValueRef result = (CApi.ValueRef) (void*) null;
		CApi.ValueRef failed = (CApi.ValueRef) (void*) null;
		switch (kind) {
		case AsyncOperationKind.OPEN: result = runtime.call (builder, operation.contract.runtime.linux ? "astra_async_linux_open" : operation.contract.runtime.threaded ? "astra_async_threaded_open" : "astra_async_virtual_open", pointer, new CApi.TypeRef[] { i32 }, new CApi.ValueRef[] { argument }, "explicit.executor");
			failed = CApi.build_icmp (builder, CApi.IntPredicate.EQ, result, CApi.const_null (pointer), "invalid.capacity");
			break;
		case AsyncOperationKind.START: if (operation.executor == null) {
				if (function.async_frame == null) {
					throw new LlvmError.LOWERING ("current start requires its exact async frame");
				}
				executor = runtime.call (builder, "astra_async_executor", pointer, new CApi.TypeRef[] { pointer }, new CApi.ValueRef[] { function.async_frame.task }, "current.executor");
		}
			var code = runtime.call (builder, "astra_async_start", i32, new CApi.TypeRef[] { pointer, pointer, pointer }, new CApi.ValueRef[] { executor, task, function.async_frame == null ? CApi.const_null (pointer) : function.async_frame.task }, "start.admission");
			failed = CApi.build_icmp (builder, CApi.IntPredicate.NE, code, CApi.const_null (i32), "start.refused");
			break;
		case AsyncOperationKind.CANCEL: if (operation.executor == null) {
				runtime.call (builder, "astra_async_cancel", nothing, new CApi.TypeRef[] { pointer }, new CApi.ValueRef[] { task });
		} else {
				runtime.call (builder, "astra_async_host_cancel", nothing, new CApi.TypeRef[] { pointer, pointer }, new CApi.ValueRef[] { executor, task });
			} break;
		case AsyncOperationKind.PUMP: result = runtime.call (builder, "astra_async_pump", i32, new CApi.TypeRef[] { pointer, i32 }, new CApi.ValueRef[] { executor, argument }, "bounded.turns");
			break;
		case AsyncOperationKind.WAIT: var waited = runtime.call (builder, "astra_async_linux_wait", i32, new CApi.TypeRef[] { pointer }, new CApi.ValueRef[] { executor }, "kernel.wait");
			failed = CApi.build_icmp (builder, CApi.IntPredicate.EQ, waited, CApi.const_null (i32), "kernel.wait.failed");
			break;
		case AsyncOperationKind.ADVANCE: var advanced = runtime.call (builder, "astra_async_advance", i32, new CApi.TypeRef[] { pointer, runtime.i64 }, new CApi.ValueRef[] { executor, CApi.build_zext (builder, argument, runtime.i64, "logical.advance") }, "advanced");
			failed = CApi.build_icmp (builder, CApi.IntPredicate.EQ, advanced, CApi.const_null (i32), "advance.overflow");
			break;
		case AsyncOperationKind.BEGIN_SHUTDOWN: runtime.call (builder, "astra_async_begin_shutdown", nothing, new CApi.TypeRef[] { pointer }, new CApi.ValueRef[] { executor });
			break;
		case AsyncOperationKind.SHUTDOWN_COMPLETE: result = runtime.call (builder, "astra_async_shutdown_complete", i32, new CApi.TypeRef[] { pointer }, new CApi.ValueRef[] { executor }, "shutdown.quiescent");
			result = CApi.build_icmp (builder, CApi.IntPredicate.NE, result, CApi.const_null (i32), "quiescent");
			break;
		case AsyncOperationKind.FINISH_SHUTDOWN: result = runtime.call (builder, "astra_async_finish_shutdown", i32, new CApi.TypeRef[] { pointer }, new CApi.ValueRef[] { executor }, "shutdown.observed");
			result = CApi.build_icmp (builder, CApi.IntPredicate.NE, result, CApi.const_null (i32), "finished");
			break;
		case AsyncOperationKind.RUN: var exception = CApi.build_alloca (builder, pointer, "root.original.exception");
			var phase = runtime.call (builder, "astra_async_run", i32, new CApi.TypeRef[] { pointer, pointer, pointer }, new CApi.ValueRef[] { executor, task, exception }, "root.observed");
			bind (operation.exception, CApi.build_load (builder, pointer, exception, "root.original.error"));
			result = CApi.build_icmp (builder, CApi.IntPredicate.EQ, phase, CApi.const_int (i32, 7, 0), "root.cancelled");
			failed = CApi.build_icmp (builder, CApi.IntPredicate.SLT, phase, CApi.const_null (i32), "root.admission.refused");
			break;
			default: throw new LlvmError.LOWERING ("unregistered exact virtual operation");
		}
		if ((void*) result != null) {
			if ((void*) CApi.type_of (result) != (void*) types.value_type (operation.contract.result)) {
				throw new LlvmError.LOWERING ("virtual operation physical result mismatch");
			}
			bind (operation.result, result);
		}
		if ((void*) failed != null) {
			var failure = append_block ("virtual.ordinary.error");
			var done = append_block ("virtual.operation.done");
			CApi.build_cond_br (builder, failed, failure, done);
			CApi.position_builder_at_end (builder, failure);
			state.end = failure;
			var error = runtime_error (operation.span, state, operation.contract.runtime.linux ? "Linux io_uring executor operation failed" : "virtual task admission refused");
			bind (operation.exception, error);
			CApi.build_br (builder, done);
			CApi.position_builder_at_end (builder, done);
			state.end = done;
		}
	}

	private void lower_task_wait(SsaTaskWait wait, int block, int position, LlvmBlockState state) throws LlvmError, NativeAbiError {
		if (function.async_frame == null) {
			throw new LlvmError.LOWERING ("await requires its exact native source frame");
		}
		var frame = function.async_frame;
		var runtime = new LlvmAsyncRuntime (artifact);
		var pointer = types.scalar (NativeScalarType.PTR);
		var i32 = types.scalar (NativeScalarType.I32);
		CApi.BasicBlockRef failure;
		var resumed = frame.enter_wait (builder, value (wait.child), wait.discard, block, position, out failure, false, wait.bridge_executor == null ? (CApi.ValueRef) null : value (wait.bridge_executor));
		var joined = append_block ("await.delivered");
		CApi.position_builder_at_end (builder, failure);
		state.end = failure;
		if (wait.discard) {
			runtime.trap (builder);
		} else {
			bind (wait.result, runtime_error (wait.span, state));
			CApi.build_br (builder, joined);
		}
		CApi.position_builder_at_end (builder, resumed);
		state.end = resumed;
		var child = runtime.call (builder, "astra_async_waited", pointer, new CApi.TypeRef[] { pointer }, new CApi.ValueRef[] { frame.task }, "joined.child");
		var phase = runtime.call (builder, "astra_async_phase", i32, new CApi.TypeRef[] { pointer }, new CApi.ValueRef[] { child }, "child.outcome");
		if (wait.discard) {
			runtime.call (builder, "astra_async_release_wait", i32, new CApi.TypeRef[] { pointer, i32 }, new CApi.ValueRef[] { frame.task, CApi.const_null (i32) });
			bind (wait.result, CApi.const_null (pointer));
			CApi.build_br (builder, joined);
		} else {
			var success = append_block ("await.success");
			var exceptional = append_block ("await.exception");
			var cancelled = append_block ("await.cancelled");
			var invalid = append_block ("await.invalid");
			var delivered = append_block ("await.observe");
			var selection = CApi.build_switch (builder, phase, invalid, 3);
			CApi.add_case (selection, CApi.const_int (i32, 5, 0), success);
			CApi.add_case (selection, CApi.const_int (i32, 6, 0), exceptional);
			CApi.add_case (selection, CApi.const_int (i32, 7, 0), cancelled);
			CApi.position_builder_at_end (builder, invalid);
			runtime.trap (builder);
			CApi.position_builder_at_end (builder, success);
			if (wait.success != null) {
				var data = runtime.call (builder, "astra_async_data", pointer, new CApi.TypeRef[] { pointer }, new CApi.ValueRef[] { child }, "child.success.storage");
				if (wait.success.buffer_result != null) {
					var pair = async_result_read (types.buffer_carrier (), data, "await.owned.buffer");
					frame.write (builder, ((SsaDefinition) wait.success.buffer_result.base_value).ordinal, async_result_extract (pair, 0, "await.buffer.base"));
					frame.write (builder, ((SsaDefinition) wait.success.buffer_result.length_value).ordinal, async_result_extract (pair, 1, "await.buffer.length"));
				} else if (wait.success.enum_result != null) {
					var slot = wait.success.enum_result;
					sum_registry.copy (builder, sum_registry.lookup (slot.definition.semantic_type.identity), enum_address (slot), data);
					enum_live (slot, true);
				} else if (wait.success.struct_result != null) {
					var group = wait.success.struct_result;
					var leaf_types = new CApi.TypeRef[group.leaves.length];
					for (int l = 0; l < leaf_types.length; l++) {
						leaf_types[l] = types.value_type (group.leaves[l].semantic_type);
					}
					var carrier_type = leaf_types.length == 1 ? leaf_types[0] : CApi.struct_type_in_context (artifact.context, leaf_types, leaf_types.length, 0);
					var carrier = async_result_read (carrier_type, data, "await.record.carrier");
					for (int l = 0; l < group.leaves.length; l++) {
						frame.write (builder, group.leaves[l].ordinal, group.leaves.length == 1 ? carrier : async_result_extract (carrier, (uint) l, "await.record.leaf"));
					}
				} else {
					frame.write (builder, wait.success.result.ordinal, async_result_read (types.value_type (wait.success.result.semantic_type), data, "await.value"));
				}
			}
			bind (wait.result, CApi.const_null (pointer));
			CApi.build_br (builder, delivered);
			CApi.position_builder_at_end (builder, exceptional);
			bind (wait.result, runtime.call (builder, "astra_async_exception", pointer, new CApi.TypeRef[] { pointer }, new CApi.ValueRef[] { child }, "original.exception"));
			CApi.build_br (builder, delivered);
			CApi.position_builder_at_end (builder, cancelled);
			runtime.call (builder, "astra_async_release_wait", i32, new CApi.TypeRef[] { pointer, i32 }, new CApi.ValueRef[] { frame.task, CApi.const_null (i32) });
			CApi.build_br (builder, frame.cancel_entry);
			CApi.position_builder_at_end (builder, delivered);
			runtime.call (builder, "astra_async_release_wait", i32, new CApi.TypeRef[] { pointer, i32 }, new CApi.ValueRef[] { frame.task, CApi.const_int (i32, 1, 0) });
			CApi.build_br (builder, joined);
		}
		CApi.position_builder_at_end (builder, joined);
		state.end = joined;
	}

	// Plain native objects have no dynamic class header. Retired frames use
	// their existing exact owner contract, just as ordinary scope cleanup does.
	private void destroy_plain_frame_owner(CApi.BuilderRef cleanup_builder, CApi.ValueRef cleanup_function, CApi.ValueRef owned, SsaCleanupContract contract, LlvmBlockState state, LlvmBufferAllocation allocator) throws LlvmError {
		var dispose = CApi.append_basic_block_in_context (artifact.context, cleanup_function, "dispose.plain.owner");
		var next = CApi.append_basic_block_in_context (artifact.context, cleanup_function, "plain.owner.disposed");
		var is_null = CApi.build_icmp (cleanup_builder, CApi.IntPredicate.EQ, owned, CApi.const_null (types.scalar (NativeScalarType.PTR)), "plain.owner.null");
		CApi.build_cond_br (cleanup_builder, is_null, next, dispose);
		CApi.position_builder_at_end (cleanup_builder, dispose);
		state.end = dispose;
		classes.release_owned (cleanup_builder, cleanup_function, allocator, contract.object_class, owned, state, "plain.owner");
		CApi.build_br (cleanup_builder, next);
		CApi.position_builder_at_end (cleanup_builder, next);
		state.end = next;
	}

	private void emit_async_destroy(SsaFunction source) throws LlvmError {
		var frame = function.async_frame;
		var destructor_builder = CApi.create_builder_in_context (artifact.context);
		var entry = CApi.append_basic_block_in_context (artifact.context, frame.destroy, "destroy.retired.frame");
		CApi.position_builder_at_end (destructor_builder, entry);
		var state = new LlvmBlockState (entry);
		var destructor_scalars = new LlvmScalarLowering (artifact, types, destructor_builder, frame.destroy);
		var allocator = new LlvmBufferAllocation (artifact, destructor_builder, frame.destroy, destructor_scalars);
		var pointer = types.scalar (NativeScalarType.PTR);
		var i32 = types.scalar (NativeScalarType.I32);
		var runtime = new LlvmAsyncRuntime (artifact);
		var task = CApi.get_param (frame.destroy, 0);
		var backing = frame.environment (destructor_builder, task);
		for (int ordered = (int) frame.plan.cleanup_count - 1; ordered >= 0; ordered--) {
			int domain = frame.plan.cleanup_domain ((uint) ordered);
			int ordinal = frame.plan.cleanup_ordinal ((uint) ordered);
			if (domain == 0) {
				int o = ordinal;
				var address = frame.field_address (destructor_builder, backing, frame.owner_field ((uint) o));
				var owned = CApi.build_load (destructor_builder, pointer, address, "retired.owner");
				artifact.class_values.add (new LlvmClassValueBinding (owned, CApi.Opcode.LOAD, pointer, new CApi.ValueRef[] { address }, "retired exact owner read"));
				var live_address = frame.field_address (destructor_builder, backing, frame.owner_field ((uint) o) + 1);
				var live = CApi.build_load (destructor_builder, CApi.int1_type_in_context (artifact.context), live_address, "retired.owner.live");
				artifact.class_values.add (new LlvmClassValueBinding (live, CApi.Opcode.LOAD, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { live_address }, "retired exact live owner selection"));
				var dispose = CApi.append_basic_block_in_context (artifact.context, frame.destroy, "dispose.live.owner");
				var next = CApi.append_basic_block_in_context (artifact.context, frame.destroy, "owner.disposed");
				var selection = CApi.build_cond_br (destructor_builder, live, dispose, next);
				artifact.class_branches.add (new LlvmClassBranchBinding (selection, live, dispose, next));
				CApi.position_builder_at_end (destructor_builder, dispose);
				state.end = dispose;
				CApi.build_store (destructor_builder, CApi.const_null (pointer), address);
				CApi.build_store (destructor_builder, CApi.const_null (CApi.int1_type_in_context (artifact.context)), live_address);
				if (frame.plan.owner ((uint) o).closure != null) {
					var contract = source.heap_owners[o].cleanup;
					if (contract.closure_type == null) {
						throw new LlvmError.LOWERING ("persistent closure lost its exact typed cleanup authority");
					}
					try {
						if (!frame.plan.owner ((uint) o).closure.same_type (NativeTypeMapper.map_type (contract.closure_type))) {
							throw new LlvmError.LOWERING ("persistent closure lost its complete callable cleanup signature");
						}
					} catch (NativeAbiError error) {
						throw new LlvmError.LOWERING ("persistent closure type: %s", error.message);
					}
					var closure_cleanup = new LlvmClosureLowering (artifact, types, destructor_builder, frame.destroy, destructor_scalars, allocator, functions, classes);
					closure_cleanup.release (owned, contract, state);
				} else if (frame.plan.owner ((uint) o).cleanup_symbol == "") {
					var contract = o < source.heap_owners.length ? source.heap_owners[o].cleanup : null;
					if (contract != null && contract.is_heap_object && !contract.object_class.polymorphic) {
						destroy_plain_frame_owner (destructor_builder, frame.destroy, owned, contract, state, allocator);
					} else {
						classes.destroy (destructor_builder, frame.destroy, owned, "retired.owner.%d".printf (o), state, allocator);
					}
				} else {
					var cleanup = cleanup_functions.lookup (cleanup_correspondence.lookup (source.heap_owners[o].cleanup));
					if (cleanup == null) {
						throw new LlvmError.LOWERING ("persistent Resource lost exact declared cleanup binding");
					}
					var arguments = new CApi.ValueRef[] {
						owned
					};
					var call = CApi.build_call (destructor_builder, cleanup.type, cleanup.value, arguments, 1, "");
					CApi.set_instruction_call_conv (call, CApi.CallConv.C);
					cleanup.calls.add ((void*) call);
					artifact.class_calls.add (new LlvmClassCallBinding (call, cleanup.value, cleanup.type, arguments, CApi.CallConv.C, "exact declared persistent Resource cleanup"));
				} CApi.build_br (destructor_builder, next);
				CApi.position_builder_at_end (destructor_builder, next);
				state.end = next;
			} else if (domain == 2) {
				int e = ordinal;
				var slot = frame.plan.enum_slot ((uint) e);
				if (!slot.owning || slot.inspection_root >= 0) {
					continue;
				}
				var flag = frame.field_address (destructor_builder, backing, frame.enum_field ((uint) e) + 1);
				var live = CApi.build_load (destructor_builder, CApi.int1_type_in_context (artifact.context), flag, "retired.enum.live");
				var active = CApi.append_basic_block_in_context (artifact.context, frame.destroy, "retired.enum.active");
				var joined = CApi.append_basic_block_in_context (artifact.context, frame.destroy, "retired.enum.disposed");
				CApi.build_cond_br (destructor_builder, live, active, joined);
				CApi.position_builder_at_end (destructor_builder, active);
				state.end = active;
				CApi.build_store (destructor_builder, CApi.const_null (CApi.int1_type_in_context (artifact.context)), flag);
				destroy_enum_payload_on (destructor_builder, frame.destroy, allocator, destructor_scalars, sum_registry.lookup (slot.identity).plan, frame.field_address (destructor_builder, backing, frame.enum_field ((uint) e)), state);
				CApi.build_br (destructor_builder, joined);
				CApi.position_builder_at_end (destructor_builder, joined);
				state.end = joined;
			} else {
				uint b = (uint) ordinal;
				var address = frame.field_address (destructor_builder, backing, frame.buffer_field (b));
				var pair = CApi.build_load (destructor_builder, types.buffer_carrier (), address, "retired.buffer");
				allocator.deallocate_buffer (CApi.build_extract_value (destructor_builder, pair, 0, "retired.buffer.base"), "retired.buffer.%u".printf (b), state, frame.plan.buffer (b).context_origin);
			}
		}
		if (source.owned_cleanup != null && source.owned_cleanup.is_buffer) {
			var discard = CApi.append_basic_block_in_context (artifact.context, frame.destroy, "discard.owned.success");
			var joined = CApi.append_basic_block_in_context (artifact.context, frame.destroy, "owned.success.disposed");
			CApi.build_cond_br (destructor_builder, CApi.build_and (destructor_builder, CApi.build_icmp (destructor_builder, CApi.IntPredicate.NE, CApi.get_param (frame.destroy, 1), CApi.const_null (i32), "discard.result"), CApi.build_load (destructor_builder, CApi.int1_type_in_context (artifact.context), frame.field_address (destructor_builder, backing, frame.result_live_field ()), "result.initialized"), "discard.initialized.result"), discard, joined);
			CApi.position_builder_at_end (destructor_builder, discard);
			state.end = discard;
			var pair = CApi.build_load (destructor_builder, types.buffer_carrier (), frame.field_address (destructor_builder, backing, 0), "owned.success");
			allocator.deallocate_buffer (CApi.build_extract_value (destructor_builder, pair, 0, "owned.success.base"), "discarded.success", state, LlvmBufferAllocation.buffer_origin (source.owned_cleanup.buffer_type));
			CApi.build_br (destructor_builder, joined);
			CApi.position_builder_at_end (destructor_builder, joined);
			state.end = joined;
		}
		if (source.return_type is EnumType && sum_registry.lookup (((EnumType) source.return_type).identity).plan.owning) {
			var discard = CApi.append_basic_block_in_context (artifact.context, frame.destroy, "discard.owning.enum.success");
			var joined = CApi.append_basic_block_in_context (artifact.context, frame.destroy, "enum.success.disposed");
			var initialized = CApi.build_load (destructor_builder, CApi.int1_type_in_context (artifact.context), frame.field_address (destructor_builder, backing, frame.result_live_field ()), "enum.result.initialized");
			var permitted = CApi.build_icmp (destructor_builder, CApi.IntPredicate.NE, CApi.get_param (frame.destroy, 1), CApi.const_null (i32), "enum.result.discard");
			CApi.build_cond_br (destructor_builder, CApi.build_and (destructor_builder, initialized, permitted, "discard.initialized.enum"), discard, joined);
			CApi.position_builder_at_end (destructor_builder, discard);
			state.end = discard;
			destroy_enum_payload_on (destructor_builder, frame.destroy, allocator, destructor_scalars, sum_registry.lookup (((EnumType) source.return_type).identity).plan, frame.field_address (destructor_builder, backing, 0), state);
			CApi.build_br (destructor_builder, joined);
			CApi.position_builder_at_end (destructor_builder, joined);
			state.end = joined;
		}
		if (frame.plan.record_result != null && frame.plan.record_result.ownership.length != 0) {
			var plan = frame.plan.record_result;
			var discard = CApi.append_basic_block_in_context (artifact.context, frame.destroy, "discard.owning.record.success");
			var joined = CApi.append_basic_block_in_context (artifact.context, frame.destroy, "record.success.disposed");
			var initialized = CApi.build_load (destructor_builder, CApi.int1_type_in_context (artifact.context), frame.field_address (destructor_builder, backing, frame.result_live_field ()), "record.result.initialized");
			var permitted = CApi.build_icmp (destructor_builder, CApi.IntPredicate.NE, CApi.get_param (frame.destroy, 1), CApi.const_null (i32), "record.result.discard");
			var condition = CApi.build_and (destructor_builder, initialized, permitted, "discard.initialized.record");
			var branch = CApi.build_cond_br (destructor_builder, condition, discard, joined);
			artifact.class_branches.add (new LlvmClassBranchBinding (branch, condition, discard, joined));
			CApi.position_builder_at_end (destructor_builder, discard);
			state.end = discard;
			var carrier = CApi.build_load (destructor_builder, types.success_result_type (function.signature), frame.field_address (destructor_builder, backing, 0), "discarded.record.success");
			var leaves = new CApi.ValueRef[plan.leaves.length];
			for (int l = 0; l < leaves.length; l++) {
				leaves[l] = plan.result_carrier == NativeStructResultCarrier.SINGLE_LEAF ? carrier : CApi.build_extract_value (destructor_builder, carrier, (uint) l, "discarded.record.leaf");
			}
			new LlvmRecordOwnership (artifact, types, classes, cleanup_correspondence, cleanup_functions).destroy_record (destructor_builder, frame.destroy, allocator, plan, leaves, state, "discarded.record");
			CApi.build_br (destructor_builder, joined);
			CApi.position_builder_at_end (destructor_builder, joined);
			state.end = joined;
		}
		var exception = runtime.call (destructor_builder, "astra_async_discarded_exception", pointer, new CApi.TypeRef[] { pointer, i32 }, new CApi.ValueRef[] { task, CApi.get_param (frame.destroy, 1) }, "discarded.original.exception");
		classes.destroy (destructor_builder, frame.destroy, exception, "retired.outcome", state, allocator);
		CApi.build_ret_void (destructor_builder);
		CApi.dispose_builder (destructor_builder);
	}

	private CApi.ValueRef async_result_read(CApi.TypeRef type, CApi.ValueRef address, string name) {
		var loaded = CApi.build_load (builder, type, address, name);
		artifact.class_values.add (new LlvmClassValueBinding (loaded, CApi.Opcode.LOAD, type, new CApi.ValueRef[] { address }, "exact observed child result carrier"));
		return loaded;
	}

	private CApi.ValueRef async_result_extract(CApi.ValueRef carrier, uint member, string name) {
		var extracted = CApi.build_extract_value (builder, carrier, member, name);
		if ((void*) CApi.is_instruction (extracted) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (extracted, CApi.Opcode.EXTRACT_VALUE, CApi.type_of (extracted), new CApi.ValueRef[] { carrier }, "exact task result group component", (int) member));
		}
		return extracted;
	}

	private CApi.ValueRef async_result_insert(CApi.ValueRef carrier, CApi.ValueRef value, uint member, string name) {
		var inserted = CApi.build_insert_value (builder, carrier, value, member, name);
		if ((void*) CApi.is_instruction (inserted) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (inserted, CApi.Opcode.INSERT_VALUE, CApi.type_of (inserted), new CApi.ValueRef[] { carrier, value }, "exact complete task result group construction", (int) member));
		}
		return inserted;
	}

	private CApi.ValueRef storage_address(SsaAddressableLocal slot) {
		return function.async_frame == null ? (CApi.ValueRef) storage.lookup (slot) : function.async_frame.storage_address (builder, (uint) slot.ordinal);
	}

	private CApi.ValueRef array_address(SsaAddressableLocal object, CApi.ValueRef index, string name) throws LlvmError, NativeAbiError {
		// Only verified constant or bounds-check results reach here. Zero
		// extension is lossless after validation, including high-bit u8/u32.
		var ordinal_type = CApi.int_type_in_context (artifact.context, 64);
		var ordinal = CApi.build_zext (builder, index, ordinal_type, name + ".ordinal");
		CApi.ValueRef[] indices = {
			CApi.const_int (ordinal_type, 0, 0), ordinal
		};
		return CApi.build_gep (builder, types.storage_type (object.semantic_type), storage_address (object), indices, indices.length, name + ".element");
	}

	private CApi.ValueRef memory_address(SsaMemoryPlace place, string name, LlvmBlockState state) throws LlvmError, NativeAbiError {
		if (place.semantic_type is StructType && (place is SsaSliceElementPlace || place is SsaArrayElementPlace)) {
			if (record_address_blocks.lookup (place) == (void*) state.end && record_addresses.contains (place)) {
				return (CApi.ValueRef) record_addresses.lookup (place);
			}
			CApi.ValueRef address;
			if (place is SsaSliceElementPlace) {
				var slice = (SsaSliceElementPlace) place;
				var pointer = CApi.build_extract_value (builder, value (slice.slice), 0, name + ".base");
				var ordinal = CApi.build_zext (builder, value (slice.index), CApi.int_type_in_context (artifact.context, 64), name + ".ordinal");
				var element = types.storage_type (slice.semantic_type);
				buffer_allocator.guard_record_offset (ordinal, element, name, state);
				address = CApi.build_gep (builder, element, pointer, &ordinal, 1, name + ".element");
			} else {
				var array = (SsaArrayElementPlace) place;
				address = array_address (array.storage, value (array.index), name);
			}
			record_address_blocks.insert (place, (void*) state.end);
			record_addresses.insert (place, (void*) address);
			return address;
		}
		var object_field = place as SsaObjectFieldPlace;
		if (object_field != null) {
			return class_field_address (structs.lookup (object_field.storage.object_class), (CApi.ValueRef) object_storage.lookup (object_field.storage), structs.field_index (object_field.field), name + ".field", object_field.field);
		}
		var slice = place as SsaSliceElementPlace;
		if (slice != null) {
			// SSA verifies a dominating bounds result for this exact view.
			var pointer = CApi.build_extract_value (builder, value (slice.slice), 0, name + ".base");
			var ordinal = CApi.build_zext (builder, value (slice.index), CApi.int_type_in_context (artifact.context, 64), name + ".ordinal");
			return CApi.build_gep (builder, types.storage_type (slice.semantic_type), pointer, &ordinal, 1, name + ".element");
		}
		var array = place as SsaArrayElementPlace;
		if (array != null) {
			return array_address (array.storage, value (array.index), name);
		}
		var local = place as SsaLocalMemoryPlace;
		if (local != null) {
			return storage_address (local.storage);
		}
		var dereference = place as SsaDereferencePlace;
		if (dereference != null) {
			var pointer = value (dereference.pointer);
			scalars.guard_nonnull (pointer, name, state);
			return pointer;
		}
		var projection = place as SsaFieldPlace;
		if (projection != null && projection.aggregate != null) {
			var pointer = memory_address (projection.aggregate, name + ".base", state);
			return CApi.build_struct_gep (builder, structs.lookup (projection.field.containing_type), pointer, structs.field_index (projection.field), name + ".field");
		}
		var direct = place as SsaDirectFieldPlace;
		CApi.ValueRef pointer;
		if (direct != null) {
			pointer = storage_address (direct.storage);
		} else {
			var indirect = (SsaIndirectFieldPlace) place;
			pointer = value (indirect.pointer);
			// Class references have a preceding explicit SSA validation;
			// incoming receivers already carry the nonnull contract.
			if (!(indirect.pointer is SsaReceiver) && !(indirect.pointer.semantic_type is ClassType)) {
				scalars.guard_nonnull (pointer, name, state);
			}
		}
		var field = ((SsaFieldPlace) place).field;
		return (field.containing_type is SsaClass) ? class_field_address (structs.lookup (field.containing_type), pointer, structs.field_index (field), name + ".field", field) : CApi.build_struct_gep (builder, structs.lookup (field.containing_type), pointer, structs.field_index (field), name + ".field");
	}

	private CApi.ValueRef slice_value(SsaSliceConstructInstruction slice, string name, LlvmBlockState state) throws LlvmError, NativeAbiError {
		var i32 = CApi.int32_type_in_context (artifact.context);
		CApi.ValueRef extent = CApi.const_int (i32, slice.array_type.length, 0);
		CApi.ValueRef pointer;
		if (slice.start == null) {
			pointer = array_address (slice.storage, CApi.const_null (i32), name);
		} else {
			var start = scalars.guard_slice_range (value (slice.start), (IntegerType) slice.start.semantic_type, value (slice.count), (IntegerType) slice.count.semantic_type, slice.array_type.length, name, state, out extent);
			if ((void*) CApi.is_constant_int (extent) != null && CApi.constant_signed (extent) == 0) {
				pointer = CApi.const_null (CApi.pointer_type_in_context (artifact.context, 0));
			} else {
				var predecessor = state.end;
				var nonempty = CApi.append_basic_block_in_context (artifact.context, function.value, name + ".nonempty");
				var joined = CApi.append_basic_block_in_context (artifact.context, function.value, name + ".view");
				var empty = CApi.build_icmp (builder, CApi.IntPredicate.EQ, extent, CApi.const_null (i32), name + ".empty");
				CApi.build_cond_br (builder, empty, joined, nonempty);
				CApi.position_builder_at_end (builder, nonempty);
				CApi.ValueRef[] indices = {
					CApi.const_null (CApi.type_of (start)), start
				};
				var address = CApi.build_gep (builder, types.storage_type (slice.array_type), storage_address (slice.storage), indices, indices.length, name + ".element");
				CApi.build_br (builder, joined);
				CApi.position_builder_at_end (builder, joined);
				var pointer_type = CApi.pointer_type_in_context (artifact.context, 0);
				pointer = CApi.build_phi (builder, pointer_type, name + ".base");
				var null_base = CApi.const_null (pointer_type);
				CApi.add_incoming (pointer, &null_base, &predecessor, 1);
				CApi.add_incoming (pointer, &address, &nonempty, 1);
				state.end = joined;
			}
		}
		var view = CApi.build_insert_value (builder, CApi.const_null (types.value_type (slice.result.semantic_type)), pointer, 0, name + ".with.base");
		return CApi.build_insert_value (builder, view, extent, 1, name);
	}

	private CApi.ValueRef buffer_address(SsaBufferPlace place, string name, LlvmBlockState state) throws LlvmError, NativeAbiError {
		if (place.record_projection != null) {
			return memory_address (place.record_projection, name, state);
		}
		return place.storage == null ? memory_address(place.field, name, state) : function.async_frame != null ? function.async_frame.buffer_address(builder, (uint) place.storage.ordinal) : (CApi.ValueRef) buffer_storage.lookup (place.storage);
	}

	private bool buffer_instruction(SsaInstruction source, LlvmBlockState state) throws LlvmError, NativeAbiError {
		var capture = source as SsaBufferSlotCaptureInstruction;
		if (capture != null) {
			string name = "buffer.slot%d".printf (next_memory++);
			var address = buffer_address (capture.place, name, state);
			var carrier = types.buffer_carrier ();
			var base_address = CApi.build_struct_gep (builder, carrier, address, 0, name + ".base");
			var count_address = CApi.build_struct_gep (builder, carrier, address, 1, name + ".length");
			var field = capture.place.field;
			var binding = new LlvmBufferSlotBinding (LlvmBufferSlotPlan.build (capture.place), function_ordinal, field == null ? buffer_origins.lookup (capture.place.storage) : null, field == null ? null : buffer_receivers.lookup (field.pointer), field == null ? null : structs.buffer_field (field.field), carrier, field == null ? (CApi.TypeRef) null : structs.lookup (field.field.containing_type), field == null ? (CApi.ValueRef) null : value (field.pointer), address, base_address, count_address);
			binding.verify ();
			buffer_slots.insert (capture, binding);
			return true;
		}
		var exchange = source as SsaBufferExchangeInstruction;
		if (exchange != null) {
			var left = buffer_slots.lookup (exchange.left_capture);
			var right = buffer_slots.lookup (exchange.right_capture);
			var plan = buffer_exchanges.lookup (exchange);
			if (left == null || right == null || plan == null) {
				throw new LlvmError.LOWERING ("exchange is missing its exact plan or captured destinations");
			}
			string name = "buffer.exchange%d".printf (next_memory++);
			CApi.ValueRef[] emitted = new CApi.ValueRef[8];
			emitted[0] = CApi.build_load (builder, types.scalar (NativeScalarType.PTR), left.base_address, name + ".left.base");
			emitted[1] = CApi.build_load (builder, types.scalar (NativeScalarType.I32), left.count_address, name + ".left.count");
			emitted[2] = CApi.build_load (builder, types.scalar (NativeScalarType.PTR), right.base_address, name + ".right.base");
			emitted[3] = CApi.build_load (builder, types.scalar (NativeScalarType.I32), right.count_address, name + ".right.count");
			emitted[4] = CApi.build_store (builder, emitted[2], left.base_address);
			emitted[5] = CApi.build_store (builder, emitted[3], left.count_address);
			emitted[6] = CApi.build_store (builder, emitted[0], right.base_address);
			emitted[7] = CApi.build_store (builder, emitted[1], right.count_address);
			var binding = new LlvmBufferExchangeBinding (plan, left, right, emitted);
			binding.verify ();
			artifact.buffer_exchanges.add (binding);
			return true;
		}
		var allocate = source as SsaBufferAllocateInstruction;
		if (allocate != null) {
			if (allocate.failure != null) {
				return true;
			}
			var count = value (allocate.count);
			var pointer = buffer_allocator.allocate_buffer (count, allocate.pair.shape.slice_type, types.storage_type (allocate.pair.shape.slice_type.element_type), "buffer.allocate%d".printf (next_memory++), state, null, allocate.allocation_context == null ? (CApi.ValueRef) null : value (allocate.allocation_context));
			bind (allocate.pair.base_value, pointer);
			bind (allocate.pair.length_value, count);
			return true;
		}
		var read = source as SsaBufferReadInstruction;
		var write = source as SsaBufferWriteInstruction;
		if (read != null || write != null) {
			var place = read == null ? write.place : read.place;
			var pair = read == null ? write.pair : read.pair;
			string name = "buffer.memory%d".printf (next_memory++);
			var address = buffer_address (place, name, state);
			var base_address = CApi.build_struct_gep (builder, types.buffer_carrier (), address, 0, name + ".base");
			var length_address = CApi.build_struct_gep (builder, types.buffer_carrier (), address, 1, name + ".length");
			if (read != null) {
				var base_load = CApi.build_load (builder, types.scalar (NativeScalarType.PTR), base_address, name + ".base.value");
				var length_load = CApi.build_load (builder, types.scalar (NativeScalarType.I32), length_address, name + ".length.value");
				bind (pair.base_value, base_load);
				bind (pair.length_value, length_load);
				scoped_access (place.storage, base_load);
				scoped_access (place.storage, length_load);
			} else {
				var base_store = CApi.build_store (builder, value (pair.base_value), base_address);
				var length_store = CApi.build_store (builder, value (pair.length_value), length_address);
				scoped_access (place.storage, base_store);
				scoped_access (place.storage, length_store);
			} return true;
		}
		var deallocate = source as SsaBufferDeallocateInstruction;
		if (deallocate != null) {
			var backing = async_buffer_reads.lookup (deallocate.pair);
			var captured = value (deallocate.pair.base_value);
			if (function.async_frame != null && backing != null) {
				CApi.build_store (builder, CApi.const_null (types.buffer_carrier ()), function.async_frame.buffer_address (builder, (uint) backing.ordinal));
			}
			buffer_allocator.deallocate_buffer (captured, "buffer.free%d".printf (next_cleanup++), state, LlvmBufferAllocation.buffer_origin (deallocate.cleanup.buffer_type));
			return true;
		}
		var borrow = source as SsaBufferBorrowInstruction;
		if (borrow != null) {
			var view = CApi.build_insert_value (builder, CApi.const_null (types.buffer_carrier ()), value (borrow.pair.base_value), 0, "buffer.borrow.base");
			bind (borrow.result, CApi.build_insert_value (builder, view, value (borrow.pair.length_value), 1, "buffer.borrow"));
			return true;
		}
		return false;
	}

	private CApi.ValueRef enum_address(SsaEnumSlot slot) throws LlvmError {
		if (function.async_frame != null) {
			return function.async_frame.enum_address (builder, (uint) slot.ordinal);
		}
		if (!enum_storage.contains (slot)) {
			throw new LlvmError.LOWERING ("enum slot has no exact function allocation");
		}
		return (CApi.ValueRef) enum_storage.lookup (slot);
	}

	private CApi.ValueRef enum_record_leaf(CApi.ValueRef pointer, SemanticType type, StructLeafPath path) throws LlvmError, NativeAbiError {
		var record = types.storage_type (type);
		for (int i = 0; i < path.depth; i++) {
			int ordinal = path.field_ordinal (i);
			pointer = sum_registry.address (builder, record, pointer, ordinal, "sum.record.leaf");
			record = CApi.struct_type_at_index (record, ordinal);
		}
		return pointer;
	}

	private bool owns_enum_slot(SsaEnumSlot slot) {
		return function.async_frame == null ? enum_liveness.contains(slot) : function.async_frame.plan.enum_slot ((uint) slot.ordinal).owning && slot.inspection_root == null;
	}

	private CApi.ValueRef enum_flag(SsaEnumSlot slot) {
		return function.async_frame == null ? (CApi.ValueRef) enum_liveness.lookup (slot) : function.async_frame.enum_flag (builder, (uint) slot.ordinal);
	}

	private void enum_live(SsaEnumSlot slot, bool live) {
		if (owns_enum_slot (slot)) {
			var selected = CApi.const_int (CApi.int1_type_in_context (artifact.context), live ? 1 : 0, 0);
			var flag = enum_flag (slot);
			var stored = CApi.build_store (builder, selected, flag);
			if (function.async_frame != null) {
				artifact.class_values.add (new LlvmClassValueBinding (stored, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { selected, flag }, "exact enum acquisition/consumer source disarm"));
			}
		}
	}

	private void destroy_enum_payload(NativeSumPlan plan, CApi.ValueRef root, LlvmBlockState state, GenericArray<EnumFieldIdentity>? retained = null) throws LlvmError {
		destroy_enum_payload_on (builder, function.value, buffer_allocator, scalars, plan, root, state, retained);
	}

	private void destroy_enum_record(CApi.BuilderRef cleanup_builder, CApi.ValueRef cleanup_function, LlvmBufferAllocation allocator, NativeStructValuePlan plan, CApi.ValueRef root, LlvmBlockState state, string name) throws LlvmError {
		var leaves = new CApi.ValueRef[plan.leaves.length];
		for (int l = 0; l < leaves.length; l++) {
			var address = sum_registry.record_leaf (cleanup_builder, plan, root, (uint) l);
			leaves[l] = sum_registry.read (cleanup_builder, types.abi_type (plan.leaves[l].abi_type), address, name + ".leaf%d".printf (l));
		}
		new LlvmRecordOwnership (artifact, types, classes, cleanup_correspondence, cleanup_functions).destroy_record (cleanup_builder, cleanup_function, allocator, plan, leaves, state, name);
	}

	private void destroy_enum_scalar(CApi.BuilderRef cleanup_builder, CApi.ValueRef cleanup_function, LlvmBufferAllocation allocator, NativeScalarOwner owner, CApi.ValueRef pointer, LlvmBlockState state, string name) throws LlvmError {
		new LlvmRecordOwnership (artifact, types, classes, cleanup_correspondence, cleanup_functions).destroy_scalar (cleanup_builder, cleanup_function, allocator, owner, pointer, state, name);
	}

	private void destroy_enum_payload_on(CApi.BuilderRef cleanup_builder, CApi.ValueRef cleanup_function, LlvmBufferAllocation cleanup_allocator, LlvmScalarLowering cleanup_scalars, NativeSumPlan plan, CApi.ValueRef root, LlvmBlockState state, GenericArray<EnumFieldIdentity>? retained = null) throws LlvmError {
		var layout = sum_registry.lookup (plan.identity);
		string name = "sum.destroy%d".printf (next_cleanup++);
		var invalid = CApi.append_basic_block_in_context (artifact.context, cleanup_function, name + ".invalid");
		var joined = CApi.append_basic_block_in_context (artifact.context, cleanup_function, name + ".done");
		var tag = sum_registry.read (cleanup_builder, types.scalar (NativeScalarType.I32), sum_registry.tag (cleanup_builder, layout, root), name + ".tag");
		var dispatch = CApi.build_switch (cleanup_builder, tag, invalid, plan.variants.length);
		for (int v = 0; v < plan.variants.length; v++) {
			var variant = plan.variants[v];
			var active = CApi.append_basic_block_in_context (artifact.context, cleanup_function, name + ".case%d".printf (v));
			CApi.add_case (dispatch, CApi.const_int (types.scalar (NativeScalarType.I32), v, 0), active);
			CApi.position_builder_at_end (cleanup_builder, active);
			state.end = active;
			for (int f = variant.fields.length - 1; f >= 0; f--) {
				var field = variant.fields[f];
				bool keep = false;
				if (retained != null) {
					foreach (var identity in retained) {
						if (identity == field.identity) {
							keep = true;
						}
					}
				}
				if (keep) {
					continue;
				}
				if (field.record_value != null) {
					destroy_enum_record (cleanup_builder, cleanup_function, cleanup_allocator, field.record_value, sum_registry.field (cleanup_builder, layout, root, field.identity), state, name + ".record%d".printf (f));
				} else if (field.scalar_owner != null) {
					var address = sum_registry.field (cleanup_builder, layout, root, field.identity);
					var pointer = sum_registry.read (cleanup_builder, types.scalar (NativeScalarType.PTR), address, name + ".owned");
					destroy_enum_scalar (cleanup_builder, cleanup_function, cleanup_allocator, field.scalar_owner, pointer, state, name + ".field%d".printf (f));
				} else if (field.buffer != null) {
					var pointer = sum_registry.field (cleanup_builder, layout, root, field.identity);
					var base_address = sum_registry.address (cleanup_builder, types.buffer_carrier (), pointer, 0, name + ".base.address");
					var base_value = sum_registry.read (cleanup_builder, types.scalar (NativeScalarType.PTR), base_address, name + ".base");
					cleanup_allocator.deallocate_buffer (base_value, name + ".field%d".printf (f), state, field.buffer.context_origin);
				} else if (field.sum != null && field.sum.owning) {
					destroy_enum_payload_on (cleanup_builder, cleanup_function, cleanup_allocator, cleanup_scalars, field.sum, sum_registry.field (cleanup_builder, layout, root, field.identity), state);
				}
			}
			CApi.build_br (cleanup_builder, joined);
		}
		CApi.position_builder_at_end (cleanup_builder, invalid);
		cleanup_scalars.emit_trap ();
		CApi.position_builder_at_end (cleanup_builder, joined);
		state.end = joined;
	}

	private void drop_enum(SsaEnumSlot slot, LlvmBlockState state) throws LlvmError {
		if (!owns_enum_slot (slot)) {
			throw new LlvmError.LOWERING ("enum cleanup requires exact owner storage, never an inspection view");
		}
		var flag = enum_flag (slot);
		string name = "sum.cleanup%d".printf (next_cleanup++);
		var active = CApi.append_basic_block_in_context (artifact.context, function.value, name + ".live");
		var joined = CApi.append_basic_block_in_context (artifact.context, function.value, name + ".done");
		CApi.build_cond_br (builder, CApi.build_load (builder, CApi.int1_type_in_context (artifact.context), flag, name + ".test"), active, joined);
		CApi.position_builder_at_end (builder, active);
		state.end = active;
		enum_live (slot, false);
		destroy_enum_payload (sum_registry.lookup (slot.definition.semantic_type.identity).plan, enum_address (slot), state);
		CApi.build_br (builder, joined);
		CApi.position_builder_at_end (builder, joined);
		state.end = joined;
	}

	private bool enum_instruction(SsaInstruction source, LlvmBlockState state) throws LlvmError, NativeAbiError {
		if (source is SsaEnumReadRecord) {
			var read = (SsaEnumReadRecord) source;
			var layout = sum_registry.lookup (read.source.definition.semantic_type.identity);
			var plan = layout.plan.variants[read.field.identity.variant.ordinal].fields[read.field.identity.ordinal].record_value;
			if (plan == null || plan.leaves.length != read.results.leaves.length) {
				throw new LlvmError.LOWERING ("enum record extraction lost its exact native physical value plan");
			}
			var root = sum_registry.field (builder, layout, enum_address (read.source), read.field.identity);
			for (int l = 0; l < read.results.leaves.length; l++) {
				bind (read.results.leaves[l], sum_registry.read (builder, types.value_type (read.results.leaves[l].semantic_type), sum_registry.record_leaf (builder, plan, root, (uint) l), "sum.extract.record.leaf"));
			}
			return true;
		}
		if (source is SsaEnumScalarCapture || source is SsaEnumScalarAbort || source is SsaEnumScalarCommit) {
			return true;
		}
		if (source is SsaEnumReadScalar) {
			var read = (SsaEnumReadScalar) source;
			var address = sum_registry.field (builder, sum_registry.lookup (read.source.definition.semantic_type.identity), enum_address (read.source), read.field.identity);
			bind (read.result, sum_registry.read (builder, types.scalar (NativeScalarType.PTR), address, "sum.extract.owner"));
			return true;
		}
		if (source is SsaEnumEndInspection || source is SsaEnumBufferCapture || source is SsaEnumBufferAbort) {
			return true;
		}
		if (source is SsaEnumReadBuffer) {
			var read = (SsaEnumReadBuffer) source;
			var pointer = sum_registry.field (builder, sum_registry.lookup (read.source.definition.semantic_type.identity), enum_address (read.source), read.field.identity);
			bind (read.pair.base_value, sum_registry.read (builder, types.scalar (NativeScalarType.PTR), sum_registry.address (builder, types.buffer_carrier (), pointer, 0, "sum.extract.base.address"), "sum.extract.base"));
			bind (read.pair.length_value, sum_registry.read (builder, types.scalar (NativeScalarType.I32), sum_registry.address (builder, types.buffer_carrier (), pointer, 1, "sum.extract.count.address"), "sum.extract.count"));
			return true;
		}
		if (source is SsaEnumFinishArm) {
			var finish = (SsaEnumFinishArm) source;
			var retained = new GenericArray<EnumFieldIdentity> ();
			for (uint f = 0; f < finish.retained_count; f++) {
				retained.add (finish.field (f).identity);
			}
			enum_live (finish.source, false);
			destroy_enum_payload (sum_registry.lookup (finish.source.definition.semantic_type.identity).plan, enum_address (finish.source), state, retained);
			return true;
		}

		if (source is SsaEnumCommit) {
			var slot = ((SsaEnumCommit) source).captured;
			enum_live (slot.reservation_source, false);
			enum_live (slot, true);
			return true;
		}
		if (source is SsaEnumDrop) {
			drop_enum (((SsaEnumDrop) source).source, state);
			return true;
		}

		var copy = source as SsaEnumCopy;
		if (copy != null) {
			sum_registry.copy (builder, sum_registry.lookup (copy.source.definition.semantic_type.identity), enum_address (copy.destination), enum_address (copy.source));
			if (copy.mode == EnumUse.MOVE && copy.destination.reservation_source == null) {
				enum_live (copy.source, false);
				enum_live (copy.destination, true);
			}
			return true;
		}
		var acquire = source as SsaEnumAcquire;
		if (acquire != null) {
			if (function.async_frame != null) {
				enum_live (acquire.destination, true);
				return true;
			}
			sum_registry.copy (builder, sum_registry.lookup (acquire.destination.definition.semantic_type.identity), enum_address (acquire.destination), value (acquire.parameter));
			enum_live (acquire.destination, true);
			return true;
		}
		var extraction = source as SsaEnumExtractSum;
		if (extraction != null) {
			var pointer = sum_registry.field (builder, sum_registry.lookup (extraction.source.definition.semantic_type.identity), enum_address (extraction.source), extraction.field.identity);
			sum_registry.copy (builder, sum_registry.lookup (extraction.destination.definition.semantic_type.identity), enum_address (extraction.destination), pointer);
			if (extraction.destination.inspection_root == null) {
				enum_live (extraction.destination, true);
			}
			return true;
		}
		var tag = source as SsaEnumTagInstruction;
		if (tag != null) {
			var pointer = sum_registry.tag (builder, sum_registry.lookup (tag.source.definition.semantic_type.identity), enum_address (tag.source));
			bind (tag.result, sum_registry.read (builder, types.value_type (tag.result.semantic_type), pointer, "v%d".printf (tag.result.ordinal)));
			return true;
		}
		var read = source as SsaEnumRead;
		if (read != null) {
			var pointer = sum_registry.field (builder, sum_registry.lookup (read.source.definition.semantic_type.identity), enum_address (read.source), read.field.identity);
			if (read.record_path != null) {
				pointer = enum_record_leaf (pointer, read.field.semantic_type, read.record_path);
			}
			bind (read.result, sum_registry.read (builder, types.value_type (read.result.semantic_type), pointer, "v%d".printf (read.result.ordinal)));
			return true;
		}
		var construction = source as SsaEnumConstruct;
		if (construction == null) {
			return false;
		}
		var layout = sum_registry.lookup (construction.destination.definition.semantic_type.identity);
		var destination = enum_address (construction.destination);
		sum_registry.clear (builder, layout, destination);
		if (!layout.plan.owning) {
			sum_registry.store (builder, CApi.const_int (types.scalar (NativeScalarType.I32), construction.variant.identity.ordinal, 0), sum_registry.tag (builder, layout, destination));
		}
		foreach (var field in construction.fields) {
			var pointer = sum_registry.field (builder, layout, destination, field.field.identity);
			if (field.record_move != null) {
				var plan = layout.plan.variants[field.field.identity.variant.ordinal].fields[field.field.identity.ordinal].record_value;
				if (plan == null || plan.leaves.length != field.leaves.length) {
					throw new LlvmError.LOWERING ("enum record store lost its exact complete physical value plan");
				}
				for (int l = 0; l < field.leaves.length; l++) {
					sum_registry.store (builder, value (field.leaves[l]), sum_registry.record_leaf (builder, plan, pointer, (uint) l));
				}
			} else if (field.buffer != null) {
				sum_registry.store (builder, value (field.buffer.base_value), sum_registry.address (builder, types.buffer_carrier (), pointer, 0, "sum.buffer.base"));
				sum_registry.store (builder, value (field.buffer.length_value), sum_registry.address (builder, types.buffer_carrier (), pointer, 1, "sum.buffer.count"));
			} else if (field.sum != null) {
				sum_registry.copy (builder, sum_registry.lookup (field.sum.definition.semantic_type.identity), pointer, enum_address (field.sum));
			} else if (field.field.semantic_type is StructType) {
				var leaves = enum_record_leaves (field.field.semantic_type);
				for (int l = 0; l < leaves.length; l++) {
					sum_registry.store (builder, value (field.leaves[l]), enum_record_leaf (pointer, field.field.semantic_type, leaves[l]));
				}
			} else {
				sum_registry.store (builder, value (field.leaves[0]), pointer);
			}
		}
		if (layout.plan.owning) {
			sum_registry.store (builder, CApi.const_int (types.scalar (NativeScalarType.I32), construction.variant.identity.ordinal, 0), sum_registry.tag (builder, layout, destination));
		}
		sum_registry.publish (builder, destination);
		enum_live (construction.destination, true);
		foreach (var field in construction.fields) {
			if (field.sum != null && field.sum.inspection_root == null) {
				enum_live (field.sum, false);
			}
		}
		return true;
	}

	private GenericArray<StructLeafPath> enum_record_leaves(SemanticType type) throws LlvmError {
		try {
			return StructLeafOrder.enumerate (type, enum_record_fields);
		} catch (StructLeafError error) {
			throw new LlvmError.LOWERING ("sum record payload: %s", error.message);
		}
	}

	private GenericArray<SemanticType>? enum_record_fields(SemanticType type) {
		return structs.fields (type);
	}

	private CApi.ValueRef[] record_field_addresses(SsaIndirectFieldPlace root, StructValueShape shape, LlvmBlockState state, string name) throws LlvmError, NativeAbiError {
		var addresses = new CApi.ValueRef[shape.leaves.length];
		for (int i = 0; i < shape.leaves.length; i++) {
			var leaf = shape.leaves[i];
			var path = leaf.storage_path ();
			SsaMemoryPlace place = root;
			for (int p = 0; p < path.depth; p++) {
				var record = structs.debug_record (place.semantic_type);
				int ordinal = path.field_ordinal (p);
				if (record == null || ordinal < 0 || ordinal >= record.fields.length) {
					throw new LlvmError.LOWERING ("inline record lost exact logical field path");
				}
				place = new SsaFieldPlace.projection (root.span, place, record.fields[ordinal]);
			}
			var address = memory_address (place, name + ".field%d".printf (i), state);
			var buffer = leaf as StructBufferLeafPath;
			if (buffer != null) {
				address = CApi.build_struct_gep (builder, types.buffer_carrier (), address, (uint) buffer.component, name + ".component%d".printf (i));
			}
			addresses[i] = address;
		}
		return addresses;
	}

	private void lower_record_field(SsaIndirectFieldPlace field, StructValueShape shape, GenericArray<SsaValue>? incoming, bool initializes, LlvmBlockState state) throws LlvmError, NativeAbiError {
		var plan = classes.inline_record (field.field);
		if (plan.leaves.length != shape.leaves.length || plan.struct_name != shape.semantic_type.display_name ()) {
			throw new LlvmError.LOWERING ("inline record commit lost exact native physical leaf plan");
		}
		string name = "record.field.%d".printf (next_memory++);
		var addresses = record_field_addresses (field, shape, state, name);
		var old = new CApi.ValueRef[initializes ? 0 : plan.leaves.length];
		for (int i = 0; i < old.length; i++) {
			old[i] = CApi.build_load (builder, types.abi_type (plan.leaves[i].abi_type), addresses[i], name + ".old%d".printf (i));
		}
		if (incoming != null) {
			if (incoming.length != addresses.length) {
				throw new LlvmError.LOWERING ("inline record commit requires every original leaf");
			}
			// Publish the complete replacement before any destructor callback.
			for (int i = 0; i < incoming.length; i++) {
				CApi.build_store (builder, value (incoming[i]), addresses[i]);
			}
		}
		if (!initializes) {
			new LlvmRecordOwnership (artifact, types, classes, cleanup_correspondence, cleanup_functions).destroy_record (
				builder, function.value, buffer_allocator, plan, old, state, name + ".retire");
		}
	}

	private void bind_record_results(SsaStructCallResults group, CApi.ValueRef carrier) throws LlvmError, NativeAbiError {
		for (int l = 0; l < group.leaves.length; l++) {
			bind (group.leaves[l], group.leaves.length == 1 ? carrier : CApi.build_extract_value (builder, carrier, l, "record.result.leaf"));
		}
	}

	private void instruction(SsaInstruction source, LlvmBlockState state) throws LlvmError, NativeAbiError {
		if (source is SsaScopedAllocator) {
			var scoped = (SsaScopedAllocator) source;
			var binding = scoped_factories.lookup (scoped.result.ordinal);
			if (binding == null) {
				throw new LlvmError.LOWERING ("scoped context has no exact native backing authority");
			}
			var call = new LlvmPolicyAllocation (artifact).open_scoped (builder, value (scoped.pair.base_value), value (scoped.pair.length_value), value (scoped.kind), value (scoped.slots));
			binding.acquire (call);
			bind (scoped.result, call);
			return;
		}
		if (source is SsaConstructorAbort) {
			constructor_abort ((SsaConstructorAbort) source, state);
			return;
		}
		if (source is SsaRecordFieldCommit) {
			var commit = (SsaRecordFieldCommit) source;
			lower_record_field (commit.destination, commit.shape, commit.leaves, commit.initializes, state);
			return;
		}
		if (source is SsaRecordFieldDrop) {
			var drop = (SsaRecordFieldDrop) source;
			lower_record_field (drop.source, drop.shape, null, false, state);
			return;
		}
		if (source is SsaLazyDrop) {
			var property = ((SsaLazyDrop) source).property_member;
			var cache = functions.lookup (property.getter).lazy_cache;
			var cleanup = property.factory.owned_cleanup;
			LlvmLazyProperties.retire (artifact, types, structs, builder, function.value, (SsaClass) property.declaring_type, cache, CApi.get_param (function.value, 0), cleanup.destructor == null ? null : functions.lookup (cleanup.destructor), buffer_allocator, state, "lazy.retire.%d".printf (next_cleanup++), classes, cleanup.object_class);
			return;
		}
		if (source is SsaSharedOperation) {
			var operation = (SsaSharedOperation) source;
			if (operation.operand.semantic_type is ClosureHandleType && ((ClosureHandleType) operation.operand.semantic_type).actor) {
				bind (operation.result, LlvmConcurrencyRuntime.call (artifact, builder, "astra_actor_clone", types.scalar (NativeScalarType.PTR), new CApi.TypeRef[] { types.scalar (NativeScalarType.PTR) }, new CApi.ValueRef[] { value (operation.operand) }));
				return;
			}
			bind (source.result, elided_copies.contains (operation) ? value (operation.operand) : shared_lowering ().operation (operation.action, value (operation.operand), state, (operation.operand.semantic_type is ClassType) ? ((ClassType) operation.operand.semantic_type).intrinsically_shared : operation.operand.semantic_type is SharedHandleType && ((SharedHandleType) operation.operand.semantic_type).payload_type.intrinsically_shared, operation.action == SharedAction.SINGLETON_SHUTDOWN ? operation.cleanup.object_class : null));
			return;
		}
		if (source is SsaActorSend) {
			var send = (SsaActorSend) source;
			var ptr = types.scalar (NativeScalarType.PTR);
			var i32 = types.scalar (NativeScalarType.I32);
			var status = closure_lowering ().actor_operation (send, value (send.sender), send.message == null ? CApi.const_null (i32) : value (send.message), state);
			var predicate = send.action == ActorAction.CANCEL ? CApi.IntPredicate.SLT : CApi.IntPredicate.NE;
			var refused = CApi.build_icmp (builder, predicate, status, CApi.const_null (i32), "actor.refused");
			artifact.class_values.add (new LlvmClassValueBinding (refused, CApi.Opcode.ICMP, types.scalar (NativeScalarType.B1), new CApi.ValueRef[] { status, CApi.const_null (i32) }, "Actor checked admission status", -1, (int) predicate));
			var admitted = state.end;
			var failure = append_block ("actor.checked.failure");
			var done = append_block ("actor.checked.done");
			var branch = CApi.build_cond_br (builder, refused, failure, done);
			artifact.class_branches.add (new LlvmClassBranchBinding (branch, refused, failure, done));
			CApi.position_builder_at_end (builder, failure);
			state.end = failure;
			var error = classes.declaration (send.error_type);
			if (error == null) {
				throw new LlvmError.LOWERING ("Actor checked failure lost nominated Error identity");
			}
			var exception = runtime_error (send.span, state, "Actor mailbox is full, closed, or cannot join this handler", error);
			var failed = state.end;
			CApi.build_br (builder, done);
			CApi.position_builder_at_end (builder, done);
			state.end = done;
			var result = CApi.build_phi (builder, ptr, "actor.checked.error");
			var empty = CApi.const_null (ptr);
			CApi.add_incoming (result, &empty, &admitted, 1);
			CApi.add_incoming (result, &exception, &failed, 1);
			bind (send.result, result);
			return;
		}
		if (source is SsaRetainedOperation) {
			var operation = (SsaRetainedOperation) source;
			CApi.ValueRef argument = operation.arguments.length == 0 ? CApi.const_null (CApi.int32_type_in_context (artifact.context)) : value (operation.arguments[0]);
			bind (operation.result, retained_lowering ().operation (operation.action, value (operation.callee), argument, state, (NativeClosureHandleType) NativeTypeMapper.map_type (operation.callee.semantic_type)));
			return;
		}
		if (source is SsaClosureBind) {
			var closure = (SsaClosureBind) source;
			bind (closure.result, closure_lowering ().bind (closure, value (closure.environment), state));
			return;
		}
		if (source is SsaClosureCall) {
			var call = (SsaClosureCall) source;
			var arguments = new CApi.ValueRef[call.arguments.length];
			for (int a = 0; a < arguments.length; a++) {
				arguments[a] = value (call.arguments[a]);
			}
			var result = closure_lowering ().invoke (call, value (call.callee), arguments, state, (CApi.ValueRef) checked_closure_slots.lookup (call));
			if (call.struct_result != null) {
				bind_record_results (call.struct_result, result);
			} else if (call.result != null) {
				bind (call.result, result);
			}
			return;
		}
		if (source is SsaFunctionValueCall) {
			var call = (SsaFunctionValueCall) source;
			var signature = (FunctionValueType) call.callee.semantic_type;
			var signature_parameters = CallableRecordGroups.physical_parameters (signature, call.struct_arguments);
			var parameter_types = new CApi.TypeRef[call.arguments.length];
			var arguments = new CApi.ValueRef[call.arguments.length];
			for (int i = 0; i < arguments.length; i++) {
				parameter_types[i] = types.value_type (signature_parameters[i]);
				arguments[i] = value (call.arguments[i]);
			}
			var code = value (call.callee);
			CApi.ValueRef result;
			if (signature is CallbackType) {
				scalars.guard_nonnull (code, "callback.invoke", state, true);
				result = callbacks ().invoke (builder, (CallbackType) signature, code, arguments);
			} else {
				var type = CApi.function_type (types.callable_result_type (signature), parameter_types, parameter_types.length, 0);
				result = CApi.build_call (builder, type, code, arguments, arguments.length, signature.result_type.kind == TypeKind.VOID ? "" : "native.function.value");
				CApi.set_instruction_call_conv (result, LlvmLowering.CALL_CONVENTION);
				artifact.class_calls.add (new LlvmClassCallBinding (result, code, type, arguments, LlvmLowering.CALL_CONVENTION, "typed native function value invocation"));
			}
			if (call.struct_result != null) {
				bind_record_results (call.struct_result, result);
			} else if (call.result != null) {
				bind (call.result, result);
			}
			return;
		}
		if (source is SsaSlotsRecordTransfer) {
			var transfer = (SsaSlotsRecordTransfer) source;
			var type = owner_slots.record_type (transfer.store.field);
			var packed = CApi.const_null (type);
			for (uint l = 0; l < transfer.leaves.length; l++) {
				var incoming = value (transfer.leaves[l]);
				var previous = packed;
				packed = CApi.build_insert_value (builder, previous, incoming, l, "slots.record.insert");
				retain_value (packed, CApi.Opcode.INSERT_VALUE, type, new CApi.ValueRef[] { previous, incoming }, "complete record slot value", (int) l);
			}
			var address = memory_address (transfer.store, "slots.record.owner", state);
			var arguments = transfer.index == null ? new CApi.ValueRef[] {
				address, packed
			} : new CApi.ValueRef[] {
				address, value (transfer.index), packed
			};
			owner_slots.invoke (builder, transfer.store.field, transfer.index == null ? "append" : "replace", arguments, "");
			return;
		}
		if (source is SsaSlotsRecordRead) {
			var read = (SsaSlotsRecordRead) source;
			var address = memory_address (read.store, "slots.record.owner", state);
			var packed = owner_slots.invoke (builder, read.store.field, read.remove ? "take" : "borrow", new CApi.ValueRef[] { address, value (read.index) }, "slots.record.result");
			for (uint l = 0; l < read.results.leaves.length; l++) {
				var extracted = CApi.build_extract_value (builder, packed, l, "slots.record.extract");
				retain_value (extracted, CApi.Opcode.EXTRACT_VALUE, types.value_type (read.results.leaves[l].semantic_type), new CApi.ValueRef[] { packed }, "complete record slot result", (int) l);
				bind (read.results.leaves[l], extracted);
			}
			return;
		}
		if (source is SsaSlotsEffect) {
			var op = (SsaSlotsEffect) source;
			var address = memory_address (op.store, "slots.owner", state);
			var arguments = op.index != null ? new CApi.ValueRef[] {
				address, value (op.index), value (op.incoming)
			} : op.incoming == null ? new CApi.ValueRef[] {
				address
			} : new CApi.ValueRef[] {
				address, value (op.incoming)
			};
			owner_slots.invoke (builder, op.store.field, op.action == SsaSlotsAction.INITIALIZE ? "initialize" : op.action == SsaSlotsAction.APPEND ? "append" : op.action == SsaSlotsAction.REPLACE ? "replace" : "drop", arguments, "");
			return;
		}
		if (source is SsaSlotsValueInstruction) {
			var op = (SsaSlotsValueInstruction) source;
			var address = memory_address (op.store, "slots.owner", state);
			var arguments = op.operand == null ? new CApi.ValueRef[] {
				address
			} : new CApi.ValueRef[] {
				address, value (op.operand)
			};
			bind (op.result, owner_slots.invoke (builder, op.store.field, op.action == OwnerSlotsAction.LENGTH ? "length" : op.action == OwnerSlotsAction.CAPACITY ? "capacity" : op.action == OwnerSlotsAction.RESERVE ? "reserve" : op.action == OwnerSlotsAction.TAKE ? "take" : "borrow", arguments, "slots.result", op.action == OwnerSlotsAction.RESERVE ? value (op.store.pointer) : (CApi.ValueRef) null));
			return;
		}

		if (source is SsaTaskCreate) {
			var creation = (SsaTaskCreate) source;
			var target = functions.lookup (creation.target);
			if (target == null || (void*) target.task_factory == null || (void*) target.task_factory_type == null) {
				throw new LlvmError.LOWERING ("task creation has no exact generated or imported factory binding");
			}
			var arguments = new CApi.ValueRef[creation.arguments.length + 3];
			for (int a = 0; a < creation.arguments.length; a++) {
				arguments[a] = value (creation.arguments[a]);
			}
			var empty = CApi.const_null (types.scalar (NativeScalarType.PTR));
			arguments[arguments.length - 3] = function.async_frame == null ? empty : function.async_frame.task;
			arguments[arguments.length - 2] = creation.allocation_context == null ? empty : new LlvmPolicyAllocation (artifact).frame_descriptor (builder, ((HandleType) creation.allocation_context.semantic_type).context_mode);
			arguments[arguments.length - 1] = creation.allocation_context == null ? empty : value (creation.allocation_context);
			var factory = creation.checked_admission ? target.task_checked_factory : target.task_factory;
			if ((void*) factory == null) {
				throw new LlvmError.LOWERING ("task creation lost its exact checked factory role");
			}
			var created = CApi.build_call (builder, target.task_factory_type, factory, arguments, arguments.length, "cold.task");
			CApi.set_instruction_call_conv (created, LlvmLowering.CALL_CONVENTION);
			artifact.class_calls.add (new LlvmClassCallBinding (created, factory, target.task_factory_type, arguments, LlvmLowering.CALL_CONVENTION, "exact cold task factory and parent association"));
			if (target.async_frame != null && target.async_frame.scoped_captures != null) {
				artifact.bind_scoped_captured_task (created, target.async_frame, factory, target.task_factory_type, arguments, creation.checked_admission);
			} else if (target.scoped_task_import != null) {
				artifact.bind_scoped_imported_capture (created, target.scoped_task_import, factory, target.task_factory_type, arguments, creation.checked_admission);
			}
			if (creation.allocation_context != null && creation.allocation_context.semantic_type.is_scoped_allocator ()) {
				artifact.bind_scoped_task_frame (created, factory, target.task_factory_type, arguments);
			}
			foreach (var argument in creation.arguments) {
				if (argument is SsaEnumArgument) {
					enum_live (((SsaEnumArgument) argument).source, false);
				}
			}
			bind (creation.result, created);
			if (creation.checked_admission) {
				var pointer = types.scalar (NativeScalarType.PTR);
				var admitted = state.end;
				var failure = append_block ("frame.admission.error");
				var done = append_block ("frame.admission.done");
				var refused = CApi.build_icmp (builder, CApi.IntPredicate.EQ, created, empty, "frame.admission.refused");
				artifact.class_values.add (new LlvmClassValueBinding (refused, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { created, empty }, "checked frame exact refusal", -1, (int) CApi.IntPredicate.EQ));
				var branch = CApi.build_cond_br (builder, refused, failure, done);
				artifact.class_branches.add (new LlvmClassBranchBinding (branch, refused, failure, done));
				CApi.position_builder_at_end (builder, failure);
				state.end = failure;
				var owner = classes.declaration (creation.target.async_body.runtime.error_type);
				if (owner == null) {
					throw new LlvmError.LOWERING ("checked frame lost nominated runtime Error class");
				}
				var error = runtime_error (creation.span, state, "task frame allocation refused", owner);
				var failed = state.end;
				CApi.build_br (builder, done);
				CApi.position_builder_at_end (builder, done);
				state.end = done;
				var exception = CApi.build_phi (builder, pointer, "frame.admission.exception");
				CApi.add_incoming (exception, &empty, &admitted, 1);
				CApi.add_incoming (exception, &error, &failed, 1);
				artifact.class_phis.add (new LlvmClassPhiBinding (exception, new CApi.ValueRef[] { empty, error }, new CApi.BasicBlockRef[] { admitted, failed }));
				bind (creation.exception_result, exception);
			}
			return;
		}
		if (source is SsaAsyncRunStatus) {
			var run = (SsaAsyncRunStatus) source;
			var integer = types.scalar (NativeScalarType.I32);
			var condition = value (run.operation.result);
			var cancelled = CApi.const_int (integer, 1, 0);
			var completed = CApi.const_null (integer);
			var tag = CApi.build_select (builder, condition, cancelled, completed, "ordinary.root.status");
			retain_value (tag, CApi.Opcode.SELECT, integer, new CApi.ValueRef[] { condition, cancelled, completed }, "exact Completed/Cancelled root status mapping");
			var layout = sum_registry.lookup (run.destination.definition.semantic_type.identity);
			sum_registry.clear (builder, layout, enum_address (run.destination));
			sum_registry.store (builder, tag, sum_registry.tag (builder, layout, enum_address (run.destination)));
			sum_registry.publish (builder, enum_address (run.destination));
			return;
		}
		if (source is SsaExecutorEnd) {
			new LlvmAsyncRuntime (artifact).call (builder, "astra_async_close", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { types.scalar (NativeScalarType.PTR) }, new CApi.ValueRef[] { value (((SsaExecutorEnd) source).source) });
			return;
		}
		if (source is SsaTaskBorrow) {
			bind (source.result, value (((SsaTaskBorrow) source).source));
			return;
		}
		if (source is SsaTaskStarted) {
			return;
		}
		if (source is SsaAsyncOperation) {
			lower_async_operation ((SsaAsyncOperation) source, state);
			return;
		}
		if (source is SsaFrameCatchEvent) {
			if (function.async_frame != null) {
				var event = (SsaFrameCatchEvent) source;
				function.async_frame.owner_update (builder, async_heap_owner_count + (uint) event.owner.ordinal, value (event.source), true);
			}
			return;
		}
		if (source is SsaTaskSuccess) {
			return;
		}
		if (source is SsaTaskAcquire) {
			return;
		}
		if (source is SsaTaskMove) {
			bind (source.result, value (((SsaTaskMove) source).source));
			return;
		}
		if (source is SsaTaskEnd) {
			var pointer = value (((SsaTaskEnd) source).source);
			var discard = append_block ("task.cold.drop");
			var done = append_block ("task.scope.end");
			CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, pointer, CApi.const_null (types.scalar (NativeScalarType.PTR)), "task.absent"), done, discard);
			CApi.position_builder_at_end (builder, discard);
			new LlvmAsyncRuntime (artifact).call (builder, "astra_async_drop", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { types.scalar (NativeScalarType.PTR) }, new CApi.ValueRef[] { pointer });
			CApi.build_br (builder, done);
			CApi.position_builder_at_end (builder, done);
			state.end = done;
			return;
		}
		if (source is SsaExceptionTransfer) {
			var pointer = value (((SsaExceptionTransfer) source).source);
			scalars.guard_nonnull (pointer, "exception.throw%d".printf (source.result.ordinal), state, true);
			bind (source.result, pointer);
			return;
		}
		if (source is SsaCatchBorrow) {
			bind (source.result, value (((SsaCatchBorrow) source).exception));
			return;
		}
		if (source is SsaExceptionStamp) {
			classes.stamp_origin (builder, value (((SsaExceptionStamp) source).exception), source.span);
			return;
		}
		if (source is SsaExceptionMatch) {
			var match = (SsaExceptionMatch) source;
			bind (source.result, classes.matches (builder, function.value, value (match.exception), match.match_type, state));
			return;
		}
		if (source is SsaRecordAcquire || source is SsaRecordMove || source is SsaRecordTake || source is SsaRecordReplace || source is SsaStructBoundary) {
			return;
		}
		if (source is SsaHeapOwnerEvent) {
			if (function.async_frame != null) {
				var event = (SsaHeapOwnerEvent) source;
				if (event.owner != null && event.action != SsaHeapOwnerAction.READ) {
					function.async_frame.owner_update (builder, (uint) event.owner.ordinal, value (event.value), event.action == SsaHeapOwnerAction.ACQUIRE);
				}
			}
			return;
		}
		if (source is SsaOwnedArgumentReservation || source is SsaOwnedArgumentAbort) {
			return;
		}
		if (source is SsaGroupCallSuccess) {
			var success = (SsaGroupCallSuccess) source;
			var call = success.call;
			var signature = functions.lookup (call.target).signature;
			if (call.enum_result != null) {
				enum_live (call.enum_result, true);
				return;
			}
			var carrier = success_read (types.success_result_type (signature), (CApi.ValueRef) exception_call_slots.lookup (call), "exception.success.group");
			if (call.buffer_result != null) {
				bind (call.buffer_result.base_value, CApi.build_extract_value (builder, carrier, 0, "buffer.result.base"));
				bind (call.buffer_result.length_value, CApi.build_extract_value (builder, carrier, 1, "buffer.result.length"));
			}
			if (call.struct_result != null) {
				for (int i = 0; i < call.struct_result.leaves.length; i++) {
					bind (call.struct_result.leaves[i], signature.struct_result.result_carrier == NativeStructResultCarrier.SINGLE_LEAF ? carrier : CApi.build_extract_value (builder, carrier, i, "struct.result.leaf"));
				}
			}
			return;
		}
		if (source is SsaClosureCallSuccess) {
			var success = (SsaClosureCallSuccess) source;
			if (((ClosureHandleType) success.call.callee.semantic_type).result_type.kind == TypeKind.VOID) {
				return;
			}
			var carrier = success_read (types.callable_result_type ((ClosureHandleType) success.call.callee.semantic_type), (CApi.ValueRef) checked_closure_slots.lookup (success.call), "closure.success");
			if (success.struct_result != null) {
				bind_record_results (success.struct_result, carrier);
			} else {
				bind (success.result, carrier);
			}
			return;
		}
		if (source is SsaCallSuccess) {
			var success = (SsaCallSuccess) source;
			bind (source.result, success_read (types.value_type (source.result.semantic_type), (CApi.ValueRef) exception_call_slots.lookup (success.call), "v%d".printf (source.result.ordinal)));
			return;
		}
		if (source is SsaClassUpcast) {
			bind (source.result, value (((SsaClassUpcast) source).reference));
			return;
		}
		if (source is SsaContinuationRegion) {
			var region = (SsaContinuationRegion) source;
			var operands = new CApi.ValueRef[region.operands.length];
			for (int i = 0; i < operands.length; i++) {
				operands[i] = value (region.operands[i]);
			}
			var result = new LlvmContinuationLowering (artifact, types).lower (continuations.lookup (region), operands, continuation_targets, builder, buffer_allocator, state);
			bind (region.result, result);
			return;
		}
		if (enum_instruction (source, state)) {
			return;
		}
		if (buffer_instruction (source, state)) {
			return;
		}
		if (source is SsaStructResultConsume || source is SsaStructParameterBorrow) {
			return;
		}
		var slice = source as SsaSliceConstructInstruction;
		if (slice != null) {
			bind (slice.result, slice_value (slice, "v%d".printf (slice.result.ordinal), state));
			return;
		}
		if (source is SsaTextLoanBind || source is SsaTextLoanEnd || source is SsaTextLoanUse || source is SsaNonNullUse) {
			return;
		}
		if (source is SsaUtf8FactoryInstruction) {
			var operation = (SsaUtf8FactoryInstruction) source;
			bind (operation.result, operation.validates ? text.validate_utf8 (builder, value (operation.input)) : value (operation.input));
			return;
		}
		if (source is SsaTextLengthInstruction) {
			var length = (SsaTextLengthInstruction) source;
			bind (length.result, CApi.build_extract_value (builder, value (length.receiver), 1, "v%d".printf (length.result.ordinal)));
			return;
		}
		var length = source as SsaSliceLengthInstruction;
		if (length != null) {
			bind (length.result, CApi.build_extract_value (builder, value (length.slice), 1, "v%d".printf (length.result.ordinal)));
			return;
		}
		var slice_bounds = source as SsaSliceBoundsCheck;
		if (slice_bounds != null) {
			var name = "slice.bounds%d".printf (next_memory++);
			var extent = CApi.build_extract_value (builder, value (slice_bounds.slice), 1, name + ".length");
			var index = value (slice_bounds.index);
			scalars.guard_slice_index (index, (IntegerType) slice_bounds.index.semantic_type, extent, name, state);
			bind (slice_bounds.result, index);
			return;
		}
		var array = source as SsaArrayInitialize;
		if (array != null) {
			if (array.record_root != null) {
				for (int i = 0; i < array.elements.length; i++) {
					CApi.build_store (builder, value (array.elements[i]), memory_address (array.record_fields[i], "array.init%d".printf (next_memory++), state));
				}
				return;
			}
			for (int i = 0; i < array.elements.length; i++) {
				var index = CApi.const_int (CApi.int32_type_in_context (artifact.context), i, 0);
				var pointer = array_address (array.storage, index, "memory%d".printf (next_memory++));
				CApi.build_store (builder, value (array.elements[i]), pointer);
			}
			return;
		}
		var bounds = source as SsaArrayBoundsCheck;
		if (bounds != null) {
			var index = value (bounds.index);
			scalars.guard_array_index (index, (IntegerType) bounds.index.semantic_type, ((ArrayType) bounds.storage.semantic_type).length, "bounds%d".printf (next_memory++), state);
			bind (bounds.result, index);
			return;
		}
		var cleanup = source as SsaCleanupInstruction;
		if (cleanup != null) {
			if (elided_releases.contains (cleanup)) {
				return;
			}
			if (cleanup.cleanup.closure_type != null) {
				closure_lowering ().release (value (cleanup.value), cleanup.cleanup, state);
				return;
			}
			if (cleanup.cleanup.shared_type != null) {
				shared_lowering ().release (value (cleanup.value), cleanup.cleanup, state);
				return;
			}
			if (cleanup.cleanup.is_object) {
				if (cleanup.cleanup.is_heap_object && ((ClassType) cleanup.cleanup.object_class.semantic_type).intrinsically_shared) {
					shared_lowering ().release (value (cleanup.value), cleanup.cleanup, state);
					return;
				}
				if (cleanup.cleanup.is_heap_object && cleanup.cleanup.object_class.polymorphic) {
					classes.destroy (builder, function.value, value (cleanup.value), "object.dynamic.free%d".printf (next_cleanup++), state, buffer_allocator, true, (ClassType) cleanup.cleanup.object_class.semantic_type);
					return;
				}
				if (cleanup.cleanup.is_heap_object && !promoted_values.contains (cleanup.value) && cleanup.cleanup.object_class.foreign_export != null && cleanup.cleanup.object_class.foreign_export.declared_api != null) {
					var pointer = value (cleanup.value);
					string name = "foreign.owner.cleanup%d".printf (next_cleanup++);
					var live = append_block (name + ".live");
					var done = append_block (name + ".done");
					var absent = CApi.build_icmp (builder, CApi.IntPredicate.EQ, pointer, CApi.const_null (types.scalar (NativeScalarType.PTR)), name + ".null");
					var branch = CApi.build_cond_br (builder, absent, done, live);
					artifact.class_branches.add (new LlvmClassBranchBinding (branch, absent, done, live));
					CApi.position_builder_at_end (builder, live);
					state.end = live;
					classes.release_owned (builder, function.value, buffer_allocator, cleanup.cleanup.object_class, pointer, state, name);
					CApi.build_br (builder, done);
					CApi.position_builder_at_end (builder, done);
					state.end = done;
					return;
				}
				var destructor = cleanup.cleanup.destructor;
				if (destructor == null) {
					classes.retire_monitor (builder, value (cleanup.value), (ClassType) cleanup.cleanup.object_class.semantic_type, state);
					if (cleanup.cleanup.is_heap_object && !promoted_values.contains (cleanup.value)) {
						buffer_allocator.deallocate (value (cleanup.value), "object.free%d".printf (next_cleanup++), state, cleanup.cleanup.object_class.allocation_policy, cleanup.cleanup.object_class.name);
					}
					return;
				}
				var callee = functions.lookup (destructor);
				if (callee == null) {
					throw new LlvmError.LOWERING ("object cleanup requires exact native DestructorSymbol binding");
				}
				var pointer = value (cleanup.value);
				string name = "cleanup%d".printf (next_cleanup++);
				var call_block = append_block (name + ".call");
				var continuation = append_block (name + ".continue");
				var is_null = CApi.build_icmp (builder, CApi.IntPredicate.EQ, pointer, CApi.const_pointer_null (CApi.type_of (pointer)), name + ".null");
				CApi.build_cond_br (builder, is_null, continuation, call_block);
				CApi.position_builder_at_end (builder, call_block);
				CApi.ValueRef[] arguments = {
					pointer
				};
				var call = CApi.build_call (builder, callee.type, callee.value, arguments, 1, "");
				CApi.set_instruction_call_conv (call, LlvmLowering.CALL_CONVENTION);
				classes.retire_monitor (builder, pointer, (ClassType) cleanup.cleanup.object_class.semantic_type, state);
				if (cleanup.cleanup.is_heap_object && !promoted_values.contains (cleanup.value)) {
					buffer_allocator.deallocate (pointer, name + ".heap.free", state, cleanup.cleanup.object_class.allocation_policy, cleanup.cleanup.object_class.name);
				}
				if (promoted_values.contains (cleanup.value)) {
					artifact.unique_receivers.add (new LlvmUniqueReceiverBinding (artifact, call, pointer));
				}
				CApi.build_br (builder, continuation);
				CApi.position_builder_at_end (builder, continuation);
				state.end = continuation;
				return;
			}
			var physical = cleanup_correspondence.lookup (cleanup.cleanup);
			var callee = physical == null ? null : cleanup_functions.lookup (physical);
			if (callee == null) {
				throw new LlvmError.LOWERING ("internal LLVM lowering error: cleanup has no exact C ABI binding");
			}
			var resource = value (cleanup.value);
			if (scoped_retirements.contains (cleanup)) {
				CApi.ValueRef[] arguments = {
					resource
				};
				var call = CApi.build_call (builder, callee.type, callee.value, arguments, 1, "");
				CApi.set_instruction_call_conv (call, CApi.CallConv.C);
				callee.calls.add ((void*) call);
				artifact.class_calls.add (new LlvmClassCallBinding (call, callee.value, callee.type, arguments, CApi.CallConv.C, "scoped context unconditional null-safe lexical retirement"));
				scoped_retirements.lookup (cleanup).retire (call);
				return;
			}
			string name = "cleanup%d".printf (next_cleanup++);
			var call_block = append_block (name + ".call");
			var continuation = append_block (name + ".continue");
			var is_null = CApi.build_icmp (builder, CApi.IntPredicate.EQ, resource, CApi.const_pointer_null (CApi.type_of (resource)), name + ".null");
			CApi.build_cond_br (builder, is_null, continuation, call_block);
			CApi.position_builder_at_end (builder, call_block);
			CApi.ValueRef[] arguments = {
				resource
			};
			var call = CApi.build_call (builder, callee.type, callee.value, arguments, 1, "");
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			callee.calls.add ((void*) call);
			artifact.class_calls.add (new LlvmClassCallBinding (call, callee.value, callee.type, arguments, CApi.CallConv.C, "exact source Resource cleanup owner"));
			CApi.build_br (builder, continuation);
			CApi.position_builder_at_end (builder, continuation);
			state.end = continuation;
			return;
		}
		var frame_restore = source as SsaFrameInputRestore;
		var frame_buffer = source as SsaFrameBufferRestore;
		var frame_record = source as SsaRecordAdmissionRestore;
		if (frame_record != null) {
			var allocation_record = frame_record as SsaFallibleRecordRestore;
			string record_prefix = allocation_record == null ? "frame.record" : "allocation.record";
			var pointer = types.scalar (NativeScalarType.PTR);
			var task = value (frame_record.admission_value ());
			var empty = CApi.const_null (pointer);
			var refused = CApi.build_icmp (builder, CApi.IntPredicate.EQ, task, empty, record_prefix + ".refused");
			artifact.class_values.add (new LlvmClassValueBinding (refused, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { task, empty }, "checked admission exact whole-record refusal", -1, (int) CApi.IntPredicate.EQ));
			for (int l = 0; l < frame_record.results.leaves.length; l++) {
				var original = value (frame_record.original.leaves[l]);
				var restored = original;
				if (frame_record.owning_leaf (l)) {
					var zero = CApi.const_null (CApi.type_of (original));
					restored = CApi.build_select (builder, refused, original, zero, record_prefix + ".leaf");
					retain_value (restored, CApi.Opcode.SELECT, CApi.type_of (original), new CApi.ValueRef[] { refused, original, zero }, "checked admission preserves exact record ownership leaf or empty");
				}
				bind (frame_record.results.leaves[l], restored);
			}
			return;
		}
		if (frame_buffer != null) {
			var pointer = types.scalar (NativeScalarType.PTR);
			var task = value (frame_buffer.creation.result);
			var empty = CApi.const_null (pointer);
			var refused = CApi.build_icmp (builder, CApi.IntPredicate.EQ, task, empty, "frame.buffer.refused");
			artifact.class_values.add (new LlvmClassValueBinding (refused, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { task, empty }, "checked frame exact buffer refusal", -1, (int) CApi.IntPredicate.EQ));
			var base_value = value (frame_buffer.argument.pair.base_value);
			var captured_length = value (frame_buffer.argument.pair.length_value);
			var zero = CApi.const_null (types.scalar (NativeScalarType.I32));
			var restored_base = CApi.build_select (builder, refused, base_value, empty, "frame.buffer.base");
			var restored_length = CApi.build_select (builder, refused, captured_length, zero, "frame.buffer.length");
			retain_value (restored_base, CApi.Opcode.SELECT, pointer, new CApi.ValueRef[] { refused, base_value, empty }, "checked frame preserves exact buffer pointer or empty");
			retain_value (restored_length, CApi.Opcode.SELECT, types.scalar (NativeScalarType.I32), new CApi.ValueRef[] { refused, captured_length, zero }, "checked frame preserves exact buffer length or zero");
			bind (frame_buffer.pair.base_value, restored_base);
			bind (frame_buffer.pair.length_value, restored_length);
			return;
		}
		if (frame_restore != null) {
			var pointer = types.scalar (NativeScalarType.PTR);
			var task = value (frame_restore.creation.result);
			var empty = CApi.const_null (pointer);
			var refused = CApi.build_icmp (builder, CApi.IntPredicate.EQ, task, empty, "frame.input.refused");
			artifact.class_values.add (new LlvmClassValueBinding (refused, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { task, empty }, "checked frame exact input refusal", -1, (int) CApi.IntPredicate.EQ));
			var original = value (frame_restore.argument.value);
			var restored = CApi.build_select (builder, refused, original, empty, "frame.input.owner");
			retain_value (restored, CApi.Opcode.SELECT, pointer, new CApi.ValueRef[] { refused, original, empty }, "checked frame preserves original capture or empty caller owner");
			bind (frame_restore.result, restored);
			return;
		}
		var restored_input = source as SsaFallibleInputRestore;
		var restored_buffer = source as SsaFallibleBufferRestore;
		if (restored_buffer != null) {
			var pointer = types.scalar (NativeScalarType.PTR);
			var receiver = value (restored_buffer.call.receiver);
			var empty = CApi.const_null (pointer);
			var refused = CApi.build_icmp (builder, CApi.IntPredicate.EQ, receiver, empty, "allocation.buffer.refused");
			artifact.class_values.add (new LlvmClassValueBinding (refused, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { receiver, empty }, "fallible allocation exact whole-buffer refusal", -1, (int) CApi.IntPredicate.EQ));
			var original_base = value (restored_buffer.argument.pair.base_value);
			var original_length = value (restored_buffer.argument.pair.length_value);
			var zero = CApi.const_null (types.scalar (NativeScalarType.I32));
			var base_value = CApi.build_select (builder, refused, original_base, empty, "allocation.buffer.base");
			var length_value = CApi.build_select (builder, refused, original_length, zero, "allocation.buffer.length");
			retain_value (base_value, CApi.Opcode.SELECT, pointer, new CApi.ValueRef[] { refused, original_base, empty }, "fallible allocation preserves exact buffer pointer or empty");
			retain_value (length_value, CApi.Opcode.SELECT, types.scalar (NativeScalarType.I32), new CApi.ValueRef[] { refused, original_length, zero }, "fallible allocation preserves exact buffer length or zero");
			bind (restored_buffer.pair.base_value, base_value);
			bind (restored_buffer.pair.length_value, length_value);
			return;
		}
		if (restored_input != null) {
			var pointer = types.scalar (NativeScalarType.PTR);
			var refused = CApi.build_icmp (builder, CApi.IntPredicate.EQ, value (restored_input.call.receiver), CApi.const_null (pointer), "allocation.input.refused");
			artifact.class_values.add (new LlvmClassValueBinding (refused, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { value (restored_input.call.receiver), CApi.const_null (pointer) }, "fallible admission exact refusal predicate", -1, (int) CApi.IntPredicate.EQ));
			var original = value (restored_input.argument.value);
			var empty = CApi.const_null (pointer);
			var restored = CApi.build_select (builder, refused, original, empty, "allocation.input.owner");
			artifact.class_values.add (new LlvmClassValueBinding (restored, CApi.Opcode.SELECT, pointer, new CApi.ValueRef[] { refused, original, empty }, "fallible admission preserves exact input or empty caller owner"));
			bind (restored_input.result, restored);
			return;
		}
		var storage_receiver = source as SsaStorageReceiverInstruction;
		if (storage_receiver != null) {
			if (promoted_objects.contains (storage_receiver.storage)) {
				promoted_values.insert (storage_receiver.result, true);
			}
			if (storage_receiver.storage.heap_allocated && !object_storage.contains (storage_receiver.storage)) {
				var owner = storage_receiver.storage.object_class;
				CApi.ValueRef pointer;
				if (owner.concurrency_policy != null && owner.concurrency_policy.singleton) {
					if (storage_receiver.storage.fallible || function.async_frame != null || (void*) monitor_guard != null) {
						throw new LlvmError.LOWERING ("Singleton acquisition requires a synchronous unguarded hosted constructor call");
					}
					var ptr = types.scalar (NativeScalarType.PTR);
					var key = LlvmConcurrencyRuntime.singleton_key (artifact, owner.name);
					var existing = LlvmConcurrencyRuntime.call (artifact, builder, "astra_singleton_enter", ptr, new CApi.TypeRef[] { ptr }, new CApi.ValueRef[] { key });
					var elected = CApi.build_icmp (builder, CApi.IntPredicate.EQ, existing, CApi.const_null (ptr), "singleton.initializer");
					singleton_initializers.insert (storage_receiver.storage, (void*) elected);
					var acquired = state.end;
					var allocate = append_block ("singleton.allocate");
					var done = append_block ("singleton.acquired");
					CApi.build_cond_br (builder, elected, allocate, done);
					CApi.position_builder_at_end (builder, allocate);
					state.end = allocate;
					var created = buffer_allocator.allocate (CApi.const_int (types.scalar (NativeScalarType.I32), 1, 0), structs.lookup (owner), "singleton.root", state, false, null, true);
					classes.initialize (builder, owner, created, "singleton.root");
					var allocated = state.end;
					CApi.build_br (builder, done);
					CApi.position_builder_at_end (builder, done);
					state.end = done;
					pointer = CApi.build_phi (builder, ptr, "singleton.owner");
					CApi.add_incoming (pointer, &existing, &acquired, 1);
					CApi.add_incoming (pointer, &created, &allocated, 1);
				} else {
					pointer = buffer_allocator.allocate (CApi.const_int (types.scalar (NativeScalarType.I32), 1, 0), structs.lookup (owner), "object%d.heap".printf (storage_receiver.storage.ordinal), state, false, null, true, owner.allocation_policy, owner.name, "object", storage_receiver.storage.fallible, storage_receiver.allocation_context == null ? (CApi.ValueRef) null : value (storage_receiver.allocation_context));
				}
				object_storage.insert (storage_receiver.storage, (void*) pointer);
				if (function.async_frame != null) {
					function.async_frame.object_write (builder, (uint) storage_receiver.storage.ordinal, pointer);
				}
			}
			var stored_pointer = function.async_frame == null ? (CApi.ValueRef) object_storage.lookup (storage_receiver.storage) : function.async_frame.object_read (builder, (uint) storage_receiver.storage.ordinal);
			if (((ReceiverType) storage_receiver.result.semantic_type).mode == ReceiverMode.INITIALIZING && !singleton_initializers.contains (storage_receiver.storage)) {
				CApi.BasicBlockRef initialized = state.end;
				if (storage_receiver.storage.fallible) {
					initialized = append_block ("allocation.init.join");
					var admitted = append_block ("allocation.init.live");
					CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, stored_pointer, CApi.const_null (types.scalar (NativeScalarType.PTR)), "allocation.failed"), initialized, admitted);
					CApi.position_builder_at_end (builder, admitted);
					state.end = admitted;
				}
				classes.initialize (builder, storage_receiver.storage.object_class, stored_pointer, "object%d".printf (storage_receiver.storage.ordinal));
				if (storage_receiver.storage.fallible) {
					CApi.build_br (builder, initialized);
					CApi.position_builder_at_end (builder, initialized);
					state.end = initialized;
				}
			}
			bind (storage_receiver.result, stored_pointer);
			return;
		}
		var object_reference = source as SsaObjectReferenceInstruction;
		if (object_reference != null) {
			if (promoted_objects.contains (object_reference.storage)) {
				promoted_values.insert (object_reference.result, true);
			}
			var pointer = function.async_frame == null ? (CApi.ValueRef) object_storage.lookup (object_reference.storage) : function.async_frame.object_read (builder, (uint) object_reference.storage.ordinal);
			// Aggregate construction has no initializing-receiver instruction.
			// Initialize hidden cache state once, before publishing its reference.
			if (object_reference.storage.object_class.constructor == null) {
				classes.initialize (builder, object_reference.storage.object_class, pointer, "object%d".printf (object_reference.storage.ordinal));
			}
			bind (object_reference.result, pointer);
			return;
		}
		var validation = source as SsaObjectValidateInstruction;
		if (validation != null) {
			if (promoted_values.contains (validation.reference)) {
				promoted_values.insert (validation.result, true);
			}
			var pointer = value (validation.reference);
			var predecessor = state.end;
			scalars.guard_nonnull (pointer, "object.guard%d".printf (validation.result.ordinal), state);
			bind (validation.result, pointer);
			if (buffer_exchanges.size () > 0) {
				buffer_receivers.lookup (validation.result).guard = CApi.block_terminator (predecessor);
			}
			return;
		}
		var address = source as SsaAddressOfInstruction;
		if (address != null) {
			bind (address.result, address.receiver_place == null ? storage_address (address.target) : memory_address (address.receiver_place, "receiver%d".printf (address.result.ordinal), state));
			return;
		}
		var place_validation = source as SsaValidatePlaceInstruction;
		if (place_validation != null) {
			memory_address (place_validation.place, "validate%d".printf (next_memory++), state);
			return;
		}
		if (source is SsaTextSnapshotDestroy) {
			var snapshot = (SsaTextSnapshotDestroy) source;
			string name = "snapshot.free%d".printf (next_cleanup++);
			var pointer = memory_address (snapshot.field, name, state);
			var text = CApi.build_load (builder, types.text_descriptor (), pointer, name + ".text");
			buffer_allocator.deallocate (CApi.build_extract_value (builder, text, 0, name + ".base"), name, state);
			return;
		}
		var load = source as SsaLoadInstruction;
		var store = source as SsaStoreInstruction;
		var initialization = source as SsaInitializeInstruction;
		if (load != null || store != null || initialization != null) {
			string memory_name = "memory%d".printf (next_memory++);
			if (load != null) {
				var pointer = memory_address (load.source, memory_name, state);
				if (load.volatile_enabled) {
					guard_volatile_alignment (pointer, load.volatile_access.alignment, memory_name, state);
				}
				var type = types.value_type (load.result.semantic_type);
				var operation = CApi.build_load (builder, type, pointer, "v%d".printf (load.result.ordinal));
				if (load.volatile_enabled) {
					CApi.set_volatile (operation, 1);
					CApi.set_alignment (operation, load.volatile_access.alignment);
					artifact.volatile_accesses.add (new LlvmVolatileAccess (operation, pointer, type, load.volatile_access.alignment, false, operation));
				}
				bind (load.result, operation);
			} else {
				var stored = value (store != null ? store.value : initialization.value);
				var pointer = memory_address (store != null ? store.target : initialization.target, memory_name, state);
				var snapshot = initialization == null ? null : initialization.target as SsaIndirectFieldPlace;
				if (snapshot != null && snapshot.field.text_snapshot) {
					stored = snapshot_text (stored, memory_name, state);
				}
				if (store != null && store.volatile_enabled) {
					guard_volatile_alignment (pointer, store.volatile_access.alignment, memory_name, state);
				}
				var operation = CApi.build_store (builder, stored, pointer);
				if (store != null && store.volatile_enabled) {
					CApi.set_volatile (operation, 1);
					CApi.set_alignment (operation, store.volatile_access.alignment);
					artifact.volatile_accesses.add (new LlvmVolatileAccess (operation, pointer, CApi.type_of (stored), store.volatile_access.alignment, true, stored));
				}
			}
			return;
		}
		string name = source.result == null ? "" : "v%d".printf (source.result.ordinal);
		var call = source as SsaCallInstruction;
		var c_call = source as SsaCCallInstruction;
		var prefix = source as SsaPrefixInstruction;
		var binary = source as SsaBinaryInstruction;
		CApi.ValueRef result;
		if (call != null) {
			if (call is SsaResultConstructionInstruction) {
				var construction = (SsaResultConstructionInstruction) call;
				classes.initialize (builder, construction.storage.object_class, value (construction.storage), "result.object");
			}
			var target = call.target;
			var callee = target == null ? null : functions.lookup (target);
			if (callee == null) {
				throw new LlvmError.LOWERING ("internal LLVM lowering error: direct call has no exact function binding");
			}
			var arguments = new CApi.ValueRef[callee.signature.physical_parameter_count];
			int component = 0;
			if (callee.signature.sum_result != null) {
				arguments[component++] = enum_address (call.enum_result);
			}
			if (callee.signature.object_result != null) {
				arguments[component++] = call.result_storage != null ? value(call.result_storage) : (CApi.ValueRef) object_storage.lookup (call.candidate_storage);
			}
			if (call.receiver != null) {
				arguments[component++] = value (call.receiver);
			}
			if (callee.signature.has_exception_success_slot) {
				arguments[component++] = (CApi.ValueRef) exception_call_slots.lookup (call);
			}
			for (int a = 0; a < call.arguments.length; a++) {
				var argument = value (call.arguments[a]);
				if (callee.signature.parameters[a].abi_type is NativeTextType || callee.signature.parameters[a].abi_type is NativeSliceType) {
					// Source evaluation is complete; extract both from this view.
					arguments[component++] = CApi.build_extract_value (builder, argument, 0, "arg%d.base".printf (a));
					arguments[component++] = CApi.build_extract_value (builder, argument, 1, "arg%d.length".printf (a));
				} else {
					arguments[component++] = argument;
				}
			}
			foreach (var argument in call.arguments) {
				if (argument is SsaEnumArgument) {
					enum_live (((SsaEnumArgument) argument).source, false);
				}
			}
			bool immutable_lazy = call.receiver != null && promoted_values.contains (call.receiver) && target.effect_facts != null && (target.effect_facts.flags & FunctionEffectFacts.LAZY_READONLY_FACTORY) != 0 && callee.lazy_body != null;
			CApi.ValueRef selected;
			if (artifact.semantic_optimizations && call.exact_target != null) {
				var exact = functions.lookup (call.exact_target);
				if (exact == null || (void*) exact.type != (void*) callee.type) {
					throw new LlvmError.LOWERING ("exact virtual target changed the verified physical native signature");
				}
				selected = exact.value;
			} else {
				selected = immutable_lazy ? callee.lazy_body.value : target.dispatch_kind == ClassDispatchKind.DIRECT ? callee.value : classes.virtual_target (builder, value (call.receiver), target.virtual_slot, target.throws_type != null, "virtual%d".printf (next_memory++));
			}
			var construction_call = call as SsaLifecycleCallInstruction;
			bool fallible_constructor = construction_call != null && construction_call.constructs && construction_call.storage.fallible;
			var allocation_refused = state.end;
			CApi.BasicBlockRef constructed = state.end;
			if (fallible_constructor) {
				constructed = append_block ("allocation.ctor.join");
				var admitted = append_block ("allocation.ctor.live");
				CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, value (call.receiver), CApi.const_null (types.scalar (NativeScalarType.PTR)), "allocation.ctor.failed"), constructed, admitted);
				CApi.position_builder_at_end (builder, admitted);
				state.end = admitted;
			}
			bool singleton_constructor = construction_call != null && construction_call.constructs && singleton_initializers.contains (construction_call.storage);
			var singleton_skip = state.end;
			CApi.BasicBlockRef singleton_done = state.end;
			if (singleton_constructor) {
				singleton_done = append_block ("singleton.constructed");
				var initialize = append_block ("singleton.initialize");
				CApi.build_cond_br (builder, (CApi.ValueRef) singleton_initializers.lookup (construction_call.storage), initialize, singleton_done);
				CApi.position_builder_at_end (builder, initialize);
				state.end = initialize;
			}
			var target_policy = target.implicit_receiver == null ? null : target.implicit_receiver.contract.instance_type as ClassType;
			if ((void*) monitor_guard != null && target_policy != null && target_policy.monitored && !(target is SsaLifecycle)) {
				if (call.receiver != policy_receiver) {
					throw new LlvmError.LOWERING ("cross-object monitor nesting requires a qualified ordered-lock operation");
				}
				LlvmConcurrencyRuntime.call (artifact, builder, "astra_monitor_internal", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { types.scalar (NativeScalarType.PTR) }, new CApi.ValueRef[] { monitor_guard });
			}
			result = CApi.build_call (builder, callee.type, selected, arguments, arguments.length, call.buffer_result != null ? "buffer.call" : call.struct_result == null ? name : "struct.call");
			CApi.set_instruction_call_conv (result, LlvmLowering.CALL_CONVENTION);
			if (call.receiver != null && promoted_values.contains (call.receiver)) {
				artifact.unique_receivers.add (new LlvmUniqueReceiverBinding (artifact, result, value (call.receiver)));
			}
			if (call.exception_result != null || call.receiver != null || callee.signature.heap_result != null) {
				artifact.class_calls.add (new LlvmClassCallBinding (result, selected, callee.type, arguments, LlvmLowering.CALL_CONVENTION, "selected native receiver and private result"));
			}
			if (callee.constructor_unwind != null) {
				if (construction_call == null || !construction_call.constructs || call.exception_result == null) {
					throw new LlvmError.LOWERING ("fallible declared construction requires exact initializing storage and checked failure edge");
				}
				var failed = append_block ("constructor.backing.failed");
				var resumed = append_block ("constructor.backing.ready");
				CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, result, CApi.const_null (types.scalar (NativeScalarType.PTR)), "constructor.backing.success"), resumed, failed);
				CApi.position_builder_at_end (builder, failed);
				state.end = failed;
				classes.retire_monitor (builder, value (call.receiver), (ClassType) construction_call.storage.object_class.semantic_type, state);
				if (construction_call.storage.heap_allocated && !promoted_values.contains (call.receiver)) {
					buffer_allocator.deallocate (value (call.receiver), "constructor.failed.backing", state, construction_call.storage.object_class.allocation_policy, construction_call.storage.object_class.name);
				}
				CApi.build_br (builder, resumed);
				CApi.position_builder_at_end (builder, resumed);
				state.end = resumed;
			}
			if (singleton_constructor) {
				var ptr = types.scalar (NativeScalarType.PTR);
				var key = LlvmConcurrencyRuntime.singleton_key (artifact, construction_call.storage.object_class.name);
				if (call.exception_result != null) {
					var publish = append_block ("singleton.publish");
					var retry = append_block ("singleton.retry");
					var finalized = append_block ("singleton.finalized");
					CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, result, CApi.const_null (ptr), "singleton.success"), publish, retry);
					CApi.position_builder_at_end (builder, retry);
					state.end = retry;
					LlvmConcurrencyRuntime.call (artifact, builder, "astra_singleton_abort", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { ptr }, new CApi.ValueRef[] { key });
					classes.retire_monitor (builder, value (call.receiver), (ClassType) construction_call.storage.object_class.semantic_type, state);
					buffer_allocator.deallocate (value (call.receiver), "singleton.failed.root", state);
					CApi.build_br (builder, finalized);
					CApi.position_builder_at_end (builder, publish);
					LlvmConcurrencyRuntime.call (artifact, builder, "astra_singleton_publish", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { ptr, ptr }, new CApi.ValueRef[] { key, value (call.receiver) });
					CApi.build_br (builder, finalized);
					CApi.position_builder_at_end (builder, finalized);
					state.end = finalized;
				} else {
					LlvmConcurrencyRuntime.call (artifact, builder, "astra_singleton_publish", CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { ptr, ptr }, new CApi.ValueRef[] { key, value (call.receiver) });
				}
				var initialized = state.end;
				CApi.build_br (builder, singleton_done);
				CApi.position_builder_at_end (builder, singleton_done);
				state.end = singleton_done;
				if (call.exception_result != null) {
					var joined = CApi.build_phi (builder, ptr, "singleton.exception");
					var none = CApi.const_null (ptr);
					CApi.add_incoming (joined, &none, &singleton_skip, 1);
					CApi.add_incoming (joined, &result, &initialized, 1);
					result = joined;
				}
			}
			if (fallible_constructor) {
				var initialized = state.end;
				CApi.build_br (builder, constructed);
				CApi.position_builder_at_end (builder, constructed);
				state.end = constructed;
				if (call.exception_result != null) {
					var pointer = types.scalar (NativeScalarType.PTR);
					var joined = CApi.build_phi (builder, pointer, "allocation.checked.exception");
					var none = CApi.const_null (pointer);
					CApi.add_incoming (joined, &none, &allocation_refused, 1);
					CApi.add_incoming (joined, &result, &initialized, 1);
					result = joined;
				}
			}
			if (call.exception_result != null) {
				bind (call.exception_result, result);
				return;
			}
			if (call.enum_result != null) {
				enum_live (call.enum_result, true);
			}
			bool sum_call = callee.signature.sum_result != null;
			foreach (var parameter in callee.signature.parameters) {
				if (parameter.abi_type is NativeSumType) {
					sum_call = true;
				}
			}
			if (sum_call) {
				artifact.sum_calls.add (new LlvmSumCall (result, callee.value, callee.type, arguments));
			}
			if (call.buffer_result != null) {
				bind (call.buffer_result.base_value, CApi.build_extract_value (builder, result, 0, "buffer.result.base"));
				bind (call.buffer_result.length_value, CApi.build_extract_value (builder, result, 1, "buffer.result.length"));
			}
			if (call.struct_result != null) {
				for (int i = 0; i < call.struct_result.leaves.length; i++) {
					var leaf = call.struct_result.leaves[i];
					bind (leaf, callee.signature.struct_result.result_carrier == NativeStructResultCarrier.SINGLE_LEAF ? result : CApi.build_extract_value (builder, result, i, "v%d".printf (leaf.ordinal)));
				}
			}
		} else if (c_call != null) {
			var target = c_call.target;
			var physical = target == null ? null : c_correspondence.lookup (target);
			var callee = physical == null ? null : c_functions.lookup (physical);
			if (callee == null) {
				throw new LlvmError.LOWERING ("internal LLVM lowering error: C call has no exact import binding");
			}
			var arguments = new CApi.ValueRef[physical.signature.physical_parameter_count];
			if (physical.signature.callback != null) {
				if ((void*) callee.callback_value == null) {
					throw new LlvmError.LOWERING ("C callback import lost its exact generated thunk");
				}
				arguments[0] = callee.callback_value;
			}
			var c_types = new LlvmCTypeMapper (artifact.context);
			CApi.ValueRef result_slot = (CApi.ValueRef) null;
			if (physical.signature.result != null && physical.signature.result.record != null && physical.signature.result.record.memory) {
				result_slot = (CApi.ValueRef) c_record_slots.lookup (c_call)[0];
				arguments[0] = result_slot;
			}
			int leaf = 0;
			for (int a = 0; a < physical.signature.parameters.length; a++) {
				var parameter = physical.signature.parameters[a];
				if (parameter.record != null && parameter.record.by_value) {
					if (parameter.record.union_projection != null && parameter.record.union_projection.tagged_union) {
						guarded_c_union = true;
						state.end = LlvmCUnionGuard.emit (artifact, builder, function.value, value (c_call.arguments[leaf]), parameter.record.union_projection.union_tag);
					}
					if (parameter.record.memory) {
						var layout = c_types.record_type (parameter.record);
						var slot = (CApi.ValueRef) c_record_slots.lookup (c_call)[a + 1];
						for (uint f = 0; f < parameter.record.fields.length; f++) {
							var field = value (c_call.arguments[leaf++]);
							var record_address = class_field_address (layout, slot, f, "c.record.field");
							var stored = CApi.build_store (builder, field, record_address);
							retain_value (stored, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { field, record_address }, "C by-value exact field staging");
						}
						arguments[parameter.physical_ordinal] = slot;
					} else {
						for (int f = 0; f < parameter.record.fields.length; f++) {
							arguments[parameter.physical_ordinal + f] = value (c_call.arguments[leaf++]);
						}
					}
					continue;
				}
				var argument = value (c_call.arguments[leaf++]);
				if (parameter.text != null) {
					arguments[parameter.text.components[0].physical_ordinal] = CApi.build_extract_value (builder, argument, 0, "carg%d.data".printf (a));
					arguments[parameter.text.components[1].physical_ordinal] = CApi.build_extract_value (builder, argument, 1, "carg%d.length".printf (a));
					callee.record_group (argument, arguments[parameter.text.components[0].physical_ordinal], arguments[parameter.text.components[1].physical_ordinal]);
				} else if (parameter.buffer != null) {
					arguments[parameter.buffer.components[0].physical_ordinal] = CApi.build_extract_value (builder, argument, 0, "carg%d.data".printf (a));
					arguments[parameter.buffer.components[1].physical_ordinal] = CApi.build_extract_value (builder, argument, 1, "carg%d.length".printf (a));
					callee.record_group (argument, arguments[parameter.buffer.components[0].physical_ordinal], arguments[parameter.buffer.components[1].physical_ordinal]);
				} else {
					arguments[parameter.physical_ordinal] = argument;
				}
			}
			result = CApi.build_call (builder, callee.type, callee.value, arguments, arguments.length, c_call.struct_result != null && physical.signature.result.record.memory ? "" : name);
			CApi.set_instruction_call_conv (result, CApi.CallConv.C);
			c_types.attributes (physical.signature, result, true);
			callee.record_call (result, arguments);
			callee.record_record_attributes (physical.signature, c_types, result, true);
			if (c_call.struct_result != null) {
				var record = physical.signature.result.record;
				if (record.union_projection != null && record.union_projection.tagged_union) {
					guarded_c_union = true;
					state.end = LlvmCUnionGuard.emit (artifact, builder, function.value, CApi.build_extract_value (builder, result, 0, "c.union.returned.tag"), record.union_projection.union_tag);
				}
				for (int f = 0; f < c_call.struct_result.leaves.length; f++) {
					var field = c_call.struct_result.leaves[f];
					var received = record.memory ? success_read (c_types.field_type (record.fields[f]), class_field_address (c_types.record_type (record), result_slot, (uint) f, "c.result.field"), "c.result.value") : record.fields.length == 1 ? result : CApi.build_extract_value (builder, result, f, "c.result.value");
					if (!record.memory && record.fields.length > 1) {
						retain_value (received, CApi.Opcode.EXTRACT_VALUE, CApi.type_of (received), new CApi.ValueRef[] { result }, "C by-value exact result projection", f);
					}
					bind (field, received);
				}
			}

		} else if (source is SsaVectorMemoryInstruction) {
			var memory = (SsaVectorMemoryInstruction) source;
			result = LlvmVectorMemory.lower (artifact, types, builder, function.value, scalars, memory.contract, value (memory.view), value (memory.offset), memory.stored == null ? (CApi.ValueRef) (void*) null : value (memory.stored), memory.stored != null, name, state);
		} else if (source is SsaVectorDotInstruction) {
			result = lower_vector_dot ((SsaVectorDotInstruction) source, name, state);
		} else if (source is SsaDspInstruction) {
			result = lower_dsp ((SsaDspInstruction) source, name);
		} else if (source is SsaIntegerShiftInstruction) {
			var shift = (SsaIntegerShiftInstruction) source;
			var immediate = shift.count as SsaIntegerConstant;
			bool known_valid = immediate != null && AstraIntegerValue.valid_shift_count (IntegerShiftKind.element_type (shift.result.semantic_type), immediate.value);
			result = scalars.shift (shift.shift_kind, shift.result.semantic_type, (IntegerType) shift.count.semantic_type, value (shift.operand), value (shift.count), known_valid, name, state);
		} else if (source is SsaNumericGuard) {
			var guard = (SsaNumericGuard) source;
			result = scalars.guard_numeric (value (guard.operand), (IntegerType) guard.destination_type, name, state);
		} else if (source is SsaNumericConversionInstruction) {
			var conversion = (SsaNumericConversionInstruction) source;
			var operand = value (conversion.operand);
			var destination = types.value_type (conversion.destination_type);
			if (conversion.conversion_kind.traps ()) {
				result = ((IntegerType) conversion.destination_type).is_signed ? CApi.build_fptosi (builder, operand, destination, name) : CApi.build_fptoui (builder, operand, destination, name);
			} else {
				result = ((IntegerType) conversion.source_type).is_signed ? CApi.build_sitofp (builder, operand, destination, name) : CApi.build_uitofp (builder, operand, destination, name);
			}
		} else if (source is SsaFloatConversionInstruction) {
			var conversion = (SsaFloatConversionInstruction) source;
			var operand = value (conversion.operand);
			var destination = types.value_type (conversion.destination_type);
			result = conversion.conversion_kind == FloatConversionKind.FLOAT_WIDEN ? CApi.build_fpext (builder, operand, destination, name) : CApi.build_fptrunc (builder, operand, destination, name);
		} else if (source is SsaIntegerConversionInstruction) {
			var conversion = (SsaIntegerConversionInstruction) source;
			var from = IntegerConversion.element_type (conversion.source_type);
			var to = IntegerConversion.element_type (conversion.destination_type);
			var operand = value (conversion.operand);
			var destination = types.value_type (conversion.destination_type);
			// Derived from source mathematical value modulo 2^destination:
			// signed widening fills ones for negatives, unsigned fills zeros;
			// narrowing retains low bits. LLVM signedness itself is absent.
			result = from.bit_width == to.bit_width ? operand : from.bit_width > to.bit_width ? CApi.build_trunc (builder, operand, destination, name) : from.is_signed ? CApi.build_sext (builder, operand, destination, name) : CApi.build_zext (builder, operand, destination, name);
			if ((from.bit_width == 64 || to.bit_width == 64) && from.bit_width != to.bit_width && (void*) CApi.is_instruction (result) != null) {
				var expected = from.bit_width > to.bit_width ? CApi.Opcode.TRUNC : from.is_signed ? CApi.Opcode.SEXT : CApi.Opcode.ZEXT;
				artifact.class_values.add (new LlvmClassValueBinding (result, expected, destination, new CApi.ValueRef[] { operand }, "wide integer conversion"));
			}
		} else if (source is SsaVectorSplatInstruction) {
			var splat = (SsaVectorSplatInstruction) source;
			var scalar = value (splat.operand);
			var index_type = types.scalar (NativeScalarType.I32);
			// Defined zero lanes even in the intermediate. Every selector is 0.
			var seed = CApi.build_insert_element (builder, CApi.const_null (types.value_type (source.result.semantic_type)), scalar, CApi.const_int (index_type, 0, 0), name + ".seed");
			var selectors = CApi.const_null (CApi.vector_type (index_type, splat.lane_count));
			result = CApi.build_shuffle_vector (builder, seed, seed, selectors, name);
		} else if (source is SsaVectorExtractInstruction) {
			var extract = (SsaVectorExtractInstruction) source;
			result = CApi.build_extract_element (builder, value (extract.vector), CApi.const_int (types.scalar (NativeScalarType.I32), extract.index.ordinal, 0), name);
		} else if (source is SsaVectorInsertInstruction) {
			var insert = (SsaVectorInsertInstruction) source;
			result = CApi.build_insert_element (builder, value (insert.vector), value (insert.replacement), CApi.const_int (types.scalar (NativeScalarType.I32), insert.index.ordinal, 0), name);
		} else if (source is SsaVectorShuffleInstruction) {
			var shuffle = (SsaVectorShuffleInstruction) source;
			var vector = value (shuffle.vector);
			var selectors = new CApi.ValueRef[shuffle.selectors.length];
			for (int i = 0; i < selectors.length; i++) {
				selectors[i] = CApi.const_int (types.scalar (NativeScalarType.I32), shuffle.selectors.at (i).ordinal, 0);
			}
			result = CApi.build_shuffle_vector (builder, vector, vector, CApi.const_vector (selectors, selectors.length), name);
		} else if (source is SsaVectorSelectInstruction) {
			var select = (SsaVectorSelectInstruction) source;
			result = CApi.build_select (builder, value (select.mask), value (select.true_value), value (select.false_value), name);
		} else if (source is SsaVectorConstructInstruction) {
			var vector = (SsaVectorConstructInstruction) source;
			var lanes = new CApi.ValueRef[vector.lanes.length];
			bool constant = true;
			for (int i = 0; i < lanes.length; i++) {
				lanes[i] = value (vector.lanes[i]);
				constant = constant && CApi.is_constant (lanes[i]) != 0;
			}
			var type = types.value_type (source.result.semantic_type);
			if (constant) {
				result = CApi.const_vector (lanes, lanes.length);
			} else {
				// All intermediate lanes are defined zero, never undef/poison.
				result = CApi.const_null (type);
				for (int i = 0; i < lanes.length; i++) {
					var index = CApi.const_int (types.scalar (NativeScalarType.I32), i, 0);
					result = CApi.build_insert_element (builder, result, lanes[i], index, i == lanes.length - 1 ? name : name + ".lane%d".printf (i));
				}
			}
		} else if (source is SsaVectorReductionInstruction) {
			var reduction = (SsaVectorReductionInstruction) source;
			var mask_type = (VectorType) reduction.operand.semantic_type;
			var mask = value (reduction.operand);
			result = CApi.build_extract_element (builder, mask, CApi.const_int (types.scalar (NativeScalarType.I32), 0, 0), name + ".lane0");
			for (int i = 1; i < mask_type.lane_count; i++) {
				var lane = CApi.build_extract_element (builder, mask, CApi.const_int (types.scalar (NativeScalarType.I32), i, 0), name + ".lane%d".printf (i));
				string step = i == mask_type.lane_count - 1 ? name : name + ".reduce%d".printf (i);
				result = reduction.operator_kind == VectorReductionOperator.ALL ? CApi.build_and (builder, result, lane, step) : CApi.build_or (builder, result, lane, step);
			}
		} else if (prefix != null) {
			result = scalars.prefix (prefix.operator_kind, prefix.operand.semantic_type, value (prefix.operand), name);
		} else if (binary != null) {
			var left = value (binary.left);
			var right = value (binary.right);
			result = (binary.left.semantic_type is StringType) ? text.equality (builder, left, right, binary.operator_kind == BinaryOperator.NOT_EQUAL, name) : scalars.binary (binary.operator_kind, binary.left.semantic_type, left, right, name, state);
		} else {
			throw new LlvmError.LOWERING ("internal LLVM lowering error: unsupported SSA instruction");
		}
		if (source.result != null) {
			bind (source.result, result);
		}
	}

	private void incoming(SsaEdge edge, CApi.BasicBlockRef predecessor) throws LlvmError, NativeAbiError {
		if (function.async_frame != null) {
			var captured = new CApi.ValueRef[edge.arguments.length];
			for (int p = 0; p < captured.length; p++) {
				captured[p] = value (edge.arguments[p]);
			}
			for (int p = 0; p < captured.length; p++) {
				function.async_frame.write (builder, edge.target.parameters[p].ordinal, captured[p]);
			}
			return;
		}
		var target = edge.target;
		for (int p = 0; p < target.parameters.length; p++) {
			var phi = value (target.parameters[p]);
			var argument = value (edge.arguments[p]);
			if ((void*) CApi.type_of (phi) != (void*) CApi.type_of (argument)) {
				throw new LlvmError.LOWERING ("internal LLVM lowering error: phi incoming type mismatch");
			}
			CApi.add_incoming (phi, &argument, &predecessor, 1);
		}
	}

	private CApi.BasicBlockRef split_edge(SsaEdge edge, string name) throws LlvmError, NativeAbiError {
		var physical = append_block (name);
		CApi.position_builder_at_end (builder, physical);
		incoming (edge, physical);
		CApi.build_br (builder, blocks.lookup (edge.target).primary);
		return physical;
	}

	private void terminator(SsaBlock source, LlvmBlockState state) throws LlvmError, NativeAbiError {
		if (source.terminator is SsaEnumInvalidTag) {
			scalars.emit_trap ();
			return;
		}
		var sum_return = source.terminator as SsaEnumReturn;
		if (sum_return != null && function.async_frame != null) {
			sum_registry.copy (builder, sum_registry.lookup (sum_return.source.definition.semantic_type.identity), function.async_frame.result_address (builder), enum_address (sum_return.source));
			enum_live (sum_return.source, false);
			function.async_frame.result_initialized (builder);
			function.async_frame.succeed (builder, (CApi.ValueRef) (void*) null);
			return;
		}
		if (sum_return != null) {
			sum_registry.copy (builder, sum_registry.lookup (sum_return.source.definition.semantic_type.identity), sum_result, enum_address (sum_return.source));
			enum_live (sum_return.source, false);
			if (function.signature.exception_plan != null) {
				CApi.build_ret (builder, CApi.const_null (types.scalar (NativeScalarType.PTR)));
			} else {
				CApi.build_ret_void (builder);
			} return;
		}
		var dispatch = source.terminator as SsaEnumDispatch;
		if (dispatch != null) {
			var layout = sum_registry.lookup (dispatch.source.definition.semantic_type.identity);
			var tag = sum_registry.read (builder, types.scalar (NativeScalarType.I32), sum_registry.tag (builder, layout, enum_address (dispatch.source)), "sum.dispatch.tag");
			var targets = new CApi.BasicBlockRef[dispatch.cases.length];
			for (int c = 0; c < targets.length; c++) {
				targets[c] = split_edge (dispatch.cases[c].edge, "sum.case.%d.%d".printf (source.ordinal, c));
			}
			var fallback = split_edge (dispatch.invalid_edge, "sum.invalid.%d".printf (source.ordinal));
			CApi.position_builder_at_end (builder, state.end);
			var instruction = CApi.build_switch (builder, tag, fallback, targets.length);
			for (int c = 0; c < targets.length; c++) {
				CApi.add_case (instruction, CApi.const_int (types.scalar (NativeScalarType.I32), c, 0), targets[c]);
			}
			artifact.sum_dispatches.add (new LlvmSumDispatch (instruction));
			return;
		}
		var request = source.terminator as SsaBufferAllocationBranch;
		if (request != null) {
			var allocation = request.allocation;
			var count = value (allocation.count);
			var failed = new LlvmBlockState (append_block ("buffer.failure.edge"));
			var pointer = buffer_allocator.allocate_buffer (count, allocation.pair.shape.slice_type, types.storage_type (allocation.pair.shape.slice_type.element_type), "buffer.allocate%d".printf (next_memory++), state, failed, allocation.allocation_context == null ? (CApi.ValueRef) null : value (allocation.allocation_context));
			bind (allocation.pair.base_value, pointer);
			bind (allocation.pair.length_value, count);
			incoming (request.success_edge, state.end);
			CApi.build_br (builder, blocks.lookup (request.success_edge.target).primary);
			CApi.position_builder_at_end (builder, failed.primary);
			incoming (request.failure_edge, failed.primary);
			CApi.build_br (builder, blocks.lookup (request.failure_edge.target).primary);
			return;
		}
		if (source.terminator is SsaAllocationFailureTrap) {
			scalars.emit_trap ();
			return;
		}
		if (source.terminator is SsaExceptionReturn) {
			var exception = value (((SsaExceptionReturn) source.terminator).value);
			if (function.async_frame != null) {
				function.async_frame.raise (builder, exception);
			} else {
				CApi.build_ret (builder, exception);
			} return;
		}
		if (source.terminator is SsaExceptionUnreachable) {
			scalars.emit_trap ();
			return;
		}
		var ret = source.terminator as SsaReturn;
		var branch = source.terminator as SsaBranch;
		var conditional = source.terminator as SsaConditionalBranch;
		if (function.async_frame != null && ret is SsaBufferReturn) {
			var returned = (SsaBufferReturn) ret;
			var carrier = async_result_insert (CApi.const_null (types.buffer_carrier ()), value (returned.pair.base_value), 0, "task.buffer.success.base");
			carrier = async_result_insert (carrier, value (returned.pair.length_value), 1, "task.buffer.success");
			function.async_frame.succeed (builder, carrier);
			return;
		}
		if (function.async_frame != null && ret is SsaStructReturn) {
			var returned = (SsaStructReturn) ret;
			CApi.ValueRef carrier;
			if (function.signature.struct_result.result_carrier == NativeStructResultCarrier.SINGLE_LEAF) {
				carrier = value (returned.leaves[0]);
			} else {
				carrier = CApi.const_null (types.success_result_type (function.signature));
				for (int l = 0; l < returned.leaves.length; l++) {
					carrier = async_result_insert (carrier, value (returned.leaves[l]), (uint) l, "task.record.leaf");
				}
			} function.async_frame.succeed (builder, carrier);
			return;
		}
		if (function.async_frame != null && (ret != null || source.terminator is SsaFunctionEnd)) {
			function.async_frame.succeed (builder, ret == null || ret.value == null ? (CApi.ValueRef) (void*) null : value (ret.value));
			return;
		}
		if (ret != null && function.signature.exception_plan != null && !(ret is SsaBufferReturn || ret is SsaStructReturn)) {
			if (ret.value != null) {
				success_write (value (ret.value));
			}
			CApi.build_ret (builder, CApi.const_null (types.scalar (NativeScalarType.PTR)));
			return;
		}
		if (ret != null) {
			if (ret is SsaBufferReturn) {
				var returned = (SsaBufferReturn) ret;
				var carrier = CApi.build_insert_value (builder, CApi.const_null (types.buffer_carrier ()), value (returned.pair.base_value), 0, "buffer.return.base");
				carrier = CApi.build_insert_value (builder, carrier, value (returned.pair.length_value), 1, "buffer.return");
				if (function.signature.exception_plan != null) {
					success_write (carrier);
					CApi.build_ret (builder, CApi.const_null (types.scalar (NativeScalarType.PTR)));
				} else {
					CApi.build_ret (builder, carrier);
				}
			} else if (ret is SsaStructReturn) {
				var returned = (SsaStructReturn) ret;
				var plan = function.signature.struct_result;
				CApi.ValueRef carrier;
				if (plan.result_carrier == NativeStructResultCarrier.SINGLE_LEAF) {
					carrier = value (returned.leaves[0]);
				} else {
					carrier = CApi.const_null (types.success_result_type (function.signature));
					for (int i = 0; i < returned.leaves.length; i++) {
						carrier = CApi.build_insert_value (builder, carrier, value (returned.leaves[i]), i, "struct.return.%d".printf (i));
					}
				}
				if (function.signature.exception_plan != null) {
					success_write (carrier);
					CApi.build_ret (builder, CApi.const_null (types.scalar (NativeScalarType.PTR)));
				} else {
					CApi.build_ret (builder, carrier);
				}
			} else if (ret.value == null) {
				CApi.build_ret_void (builder);
			} else {
				var returned = value (ret.value);
				if ((void*) CApi.type_of (returned) != (void*) types.result_type (function.signature.result)) {
					throw new LlvmError.LOWERING ("internal LLVM lowering error: return physical type mismatch");
				}
				CApi.build_ret (builder, returned);
			}
		} else if (source.terminator is SsaFunctionEnd) {
			if (function.signature.result != null || function.signature.struct_result != null || function.signature.buffer_result != null) {
				throw new LlvmError.LOWERING ("internal LLVM lowering error: non-void function reaches function-end");
			}
			if (function.signature.exception_plan != null) {
				CApi.build_ret (builder, CApi.const_null (types.scalar (NativeScalarType.PTR)));
			} else {
				CApi.build_ret_void (builder);
			}
		} else if (branch != null) {
			incoming (branch.edge, state.end);
			CApi.build_br (builder, blocks.lookup (branch.edge.target).primary);
		} else if (conditional != null) {
			var condition = value (conditional.condition);
			var true_block = blocks.lookup (conditional.true_edge.target).primary;
			var false_block = blocks.lookup (conditional.false_edge.target).primary;
			if (conditional.true_edge.target == conditional.false_edge.target) {
				true_block = split_edge (conditional.true_edge, "b%d.edge.true".printf (source.ordinal));
				false_block = split_edge (conditional.false_edge, "b%d.edge.false".printf (source.ordinal));
				CApi.position_builder_at_end (builder, state.end);
			} else {
				incoming (conditional.true_edge, state.end);
				incoming (conditional.false_edge, state.end);
			}
			var instruction = CApi.build_cond_br (builder, condition, true_block, false_block);
			if (function.signature.exception_plan != null || artifact.class_layouts.length != 0) {
				artifact.class_branches.add (new LlvmClassBranchBinding (instruction, condition, true_block, false_block));
			}
		} else {
			throw new LlvmError.LOWERING ("internal LLVM lowering error: unsupported SSA terminator");
		}
	}

}
}
