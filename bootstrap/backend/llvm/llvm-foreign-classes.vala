// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Source;

namespace Astra.Backend.LLVM {
internal class LlvmForeignRecordLayoutBinding : Object {
	private ForeignValueType declaration;
	private CApi.TypeRef storage;
	internal LlvmForeignRecordLayoutBinding (ForeignValueType declaration, CApi.TypeRef storage) {
		this.declaration = declaration;
		this.storage = storage;
	}

	internal static CApi.TypeRef storage_type(LlvmModuleArtifact artifact, LlvmTypeMapper types, ForeignValueType declaration) throws LlvmError {
		if (!declaration.valid () || declaration.kind != ForeignValueKind.RECORD) {
			throw new LlvmError.LOWERING ("foreign record storage requires a valid scalar POD declaration");
		}
		var fields = new CApi.TypeRef[declaration.field_count];
		for (uint f = 0; f < declaration.field_count; f++) {
			fields[f] = types.scalar (NativeForeignApi.scalar (declaration.field (f).kind));
		}
		var storage = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		artifact.class_layouts.add (new LlvmClassLayoutBinding (storage, fields));
		if (artifact.class_target == null) {
			artifact.class_target = new LlvmTargetMachineArtifact (0, artifact.selected_target);
		}
		LlvmBufferAllocation.qualify (artifact.class_target.triple);
		var witness = new LlvmForeignRecordLayoutBinding (declaration, storage);
		witness.verify (artifact.class_target.enum_target_data (artifact));
		artifact.foreign_records.add (witness);
		return storage;
	}

	internal void verify(CApi.TargetDataRef data) throws LlvmError {
		if (!declaration.valid () || declaration.kind != ForeignValueKind.RECORD || CApi.pointer_size (data) != 8 || CApi.count_struct_element_types (storage) != declaration.field_count || CApi.abi_size_of_type (data, storage) != CAbiClassAdapter.record_size (declaration) || CApi.abi_alignment_of_type (data, storage) != CAbiClassAdapter.record_alignment (declaration)) {
			throw new LlvmError.VERIFICATION ("foreign POD lost natural target size/alignment/field authority");
		}
		for (uint f = 0; f < declaration.field_count; f++) {
			var field = CApi.struct_type_at_index (storage, f);
			if (CApi.offset_of_element (data, storage, f) != CAbiClassAdapter.record_offset (declaration, f) || CApi.abi_size_of_type (data, field) != CAbiClassAdapter.field_size (declaration.field (f).kind) || CApi.abi_alignment_of_type (data, field) != CAbiClassAdapter.field_size (declaration.field (f).kind)) {
				throw new LlvmError.VERIFICATION ("foreign POD field differs from its declared natural C storage");
			}
		}
	}

}
internal class LlvmForeignFunctionBinding : Object {
	private CApi.ValueRef function;
	private CApi.TypeRef type;
	private string symbol;
	private LlvmSumSequence sequence;
	private uint[] bool_parameters;
	internal LlvmForeignFunctionBinding (CApi.ValueRef function, CApi.TypeRef type, string symbol, uint[]? bool_parameters = null) {
		this.function = function;
		this.type = type;
		this.symbol = symbol;
		this.bool_parameters = bool_parameters == null ? null : bool_parameters.copy ();
		sequence = new LlvmSumSequence (function, true);
	}

	internal void verify() throws LlvmError {
		size_t length;
		if (CApi.value_name (function, out length) != symbol || length != symbol.length || (void*) CApi.global_value_type (function) != (void*) type || CApi.function_call_conv (function) != CApi.CallConv.C || CApi.get_linkage (function) != CApi.Linkage.EXTERNAL) {
			throw new LlvmError.VERIFICATION ("foreign Class wrapper lost its exact C symbol/signature/convention");
		}
		for (uint p = 0; p <= CApi.count_params (function) + 1; p++) {
			uint index = p == 0 ? uint.MAX : p - 1;
			bool expected = false;
			foreach (uint parameter in bool_parameters) {
				expected |= parameter == index;
			}
			var attribute = CApi.enum_attribute (function, index, CApi.enum_attribute_kind ("zeroext", 7));
			if (CApi.attribute_count (function, index) != (expected ? 1 : 0) || expected && ((void*) attribute == null || CApi.enum_attribute_value (attribute) != 0)) {
				throw new LlvmError.VERIFICATION ("foreign Class wrapper lost exact proved C99 bool attributes");
			}
		}
		sequence.verify ();
	}

}

// Construction-local emitter. Native roots, counts and property bodies remain
// owned by the existing native pipeline. The C wrapper is a separate cache;
// its final retirement is attached to native last-strong destruction.
internal class LlvmForeignClasses : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private LlvmStructRegistry structs;
	private LlvmClassRuntime classes;
	private LlvmTextLowering text;
	private HashTable<SsaFunction, LlvmFunctionBinding> functions;
	private HashTable<CAbiCleanupFunction, LlvmCFunctionBinding> cleanup_functions;
	private SsaClass owner;
	private NativeClassPlan plan;
	private CAbiClassAdapter adapter;
	private CApi.TypeRef pointer;
	private CApi.TypeRef word;
	private CApi.TypeRef wide;
	private CApi.TypeRef control;
	private CApi.TypeRef weak_control;
	private CApi.BuilderRef builder;
	private CApi.ValueRef function;
	private CApi.TypeRef function_type;
	private string active_symbol;
	private LlvmBlockState state;
	private LlvmScalarLowering scalars;
	private LlvmBufferAllocation allocator;
	private LlvmSharedLowering shared;
	private int serial;
	private uint[] declared_bool_parameters;
	private CApi.ValueRef declared_error;
	private CApi.ValueRef[] declared_allocations;
	private CApi.ValueRef[] declared_holds;
	private SsaClass?[] declared_held_classes;
	private LlvmCFunctionBinding?[] declared_held_resources;
	private CApi.ValueRef declared_provisional_root;
	private SsaClass? declared_provisional_class;
	private LlvmCFunctionBinding? declared_provisional_resource;
	private HashTable<string, void*> record_types = new HashTable<string, void*> (str_hash, str_equal);

	internal static CApi.TypeRef control_type(LlvmModuleArtifact artifact, LlvmTypeMapper types, bool declared = false) throws LlvmError {
		var pointer = types.scalar (NativeScalarType.PTR);
		CApi.TypeRef[] fields = {
			pointer, types.scalar (NativeScalarType.U64), pointer, pointer
		};
		if (declared) {
			fields += types.scalar (NativeScalarType.I32);
			fields += types.scalar (NativeScalarType.U64);
		}
		var result = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		artifact.class_layouts.add (new LlvmClassLayoutBinding (result, fields));
		return result;
	}

	internal static CApi.ValueRef cache_address(LlvmModuleArtifact artifact, LlvmStructRegistry structs, NativeAbiProgram native, CApi.BuilderRef builder, CApi.ValueRef root, SsaClass owner) throws LlvmError {
		if (owner.foreign_export == null || owner.parent_class != null || owner.concurrency_policy == null && owner.foreign_export.declared_api == null) {
			throw new LlvmError.LOWERING ("foreign wrapper cache requires its admitted independent native root");
		}
		var layout = structs.lookup (owner);
		uint member = (uint) ((owner.concurrency_policy == null ? 0 : 6) + owner.fields.length + native.classes[owner.ordinal].lazy_caches.length * 2 + (owner.foreign_export.declared_api == null ? 0 : 1));
		var result = CApi.build_struct_gep (builder, layout, root, member, "foreign.cache.address");
		artifact.class_addresses.add (new LlvmClassAddressBinding (result, root, layout, member));
		return result;
	}

	internal static CApi.ValueRef root_context_address(LlvmModuleArtifact artifact, LlvmStructRegistry structs, NativeAbiProgram native, CApi.BuilderRef builder, CApi.ValueRef root, SsaClass owner) throws LlvmError {
		if (owner.foreign_export == null || owner.foreign_export.declared_api == null || owner.parent_class != null) {
			throw new LlvmError.LOWERING ("native foreign context requires its exact declared independent root");
		}
		uint member = (uint) ((owner.concurrency_policy == null ? 0 : 6) + owner.fields.length + native.classes[owner.ordinal].lazy_caches.length * 2);
		return address (artifact, builder, structs.lookup (owner), root, member);
	}

	private static CApi.ValueRef address(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.TypeRef layout, CApi.ValueRef root, uint member) {
		var result = CApi.build_struct_gep (builder, layout, root, member, "foreign.member");
		artifact.class_addresses.add (new LlvmClassAddressBinding (result, root, layout, member));
		return result;
	}

	private static CApi.ValueRef load(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.TypeRef type, CApi.ValueRef place) {
		var result = CApi.build_load (builder, type, place, "foreign.read");
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.LOAD, type, new CApi.ValueRef[] { place }, "foreign exact wrapper/cache read"));
		return result;
	}

	private static void store(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.ValueRef value, CApi.ValueRef place) {
		var result = CApi.build_store (builder, value, place);
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.STORE, CApi.void_type_in_context (artifact.context), new CApi.ValueRef[] { value, place }, "foreign exact wrapper/cache publication"));
	}

	private static CApi.ValueRef compare(LlvmModuleArtifact artifact, CApi.BuilderRef builder, CApi.IntPredicate predicate, CApi.ValueRef left, CApi.ValueRef right, string name) {
		var result = CApi.build_icmp (builder, predicate, left, right, name);
		if ((void*) CApi.is_instruction (result) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.ICMP, CApi.int1_type_in_context (artifact.context), new CApi.ValueRef[] { left, right }, "foreign exact null/thread/count guard", -1, (int) predicate));
		}
		return result;
	}

	internal static void retire_cache(LlvmModuleArtifact artifact, LlvmTypeMapper types, LlvmStructRegistry structs, NativeAbiProgram native, CApi.BuilderRef builder, CApi.ValueRef function, CApi.ValueRef root, SsaClass owner, LlvmBlockState state, LlvmBufferAllocation allocator) throws LlvmError {
		var pointer = types.scalar (NativeScalarType.PTR);
		var place = cache_address (artifact, structs, native, builder, root, owner);
		var cache = load (artifact, builder, pointer, place);
		store (artifact, builder, CApi.const_null (pointer), place);
		var live = CApi.append_basic_block_in_context (artifact.context, function, "foreign.retire.live");
		var call = CApi.append_basic_block_in_context (artifact.context, function, "foreign.retire.personality");
		var free = CApi.append_basic_block_in_context (artifact.context, function, "foreign.retire.control");
		var done = CApi.append_basic_block_in_context (artifact.context, function, "foreign.retire.done");
		CApi.build_cond_br (builder, compare (artifact, builder, CApi.IntPredicate.EQ, cache, CApi.const_null (pointer), "foreign.cache.empty"), done, live);
		CApi.position_builder_at_end (builder, live);
		state.end = live;
		var layout = control_type (artifact, types, owner.foreign_export.declared_api != null);
		var personality = load (artifact, builder, pointer, address (artifact, builder, layout, cache, 2));
		var destroy = load (artifact, builder, pointer, address (artifact, builder, layout, cache, 3));
		CApi.build_cond_br (builder, compare (artifact, builder, CApi.IntPredicate.EQ, destroy, CApi.const_null (pointer), "foreign.personality.absent"), free, call);
		CApi.position_builder_at_end (builder, call);
		state.end = call;
		var signature = CApi.function_type (CApi.void_type_in_context (artifact.context), &pointer, 1, 0);
		var invoked = CApi.build_call (builder, signature, destroy, &personality, 1, "");
		CApi.set_instruction_call_conv (invoked, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (invoked, destroy, signature, new CApi.ValueRef[] { personality }, CApi.CallConv.C, "last native strong personality retirement"));
		CApi.build_br (builder, free);
		CApi.position_builder_at_end (builder, free);
		state.end = free;
		allocator.deallocate (cache, "foreign.control.free", state);
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
	}

	internal static void begin_retirement(LlvmModuleArtifact artifact, LlvmTypeMapper types, LlvmStructRegistry structs, NativeAbiProgram native, CApi.BuilderRef builder, CApi.ValueRef function, CApi.ValueRef root, SsaClass owner, LlvmBlockState state) throws LlvmError {
		if (owner.foreign_export == null || owner.foreign_export.declared_api == null) {
			return;
		}
		var pointer = types.scalar (NativeScalarType.PTR);
		var inspect = CApi.append_basic_block_in_context (artifact.context, function, "foreign.retirement.inspect");
		var present = CApi.append_basic_block_in_context (artifact.context, function, "foreign.retirement.present");
		var done = CApi.append_basic_block_in_context (artifact.context, function, "foreign.retirement.admitted");
		CApi.build_cond_br (builder, compare (artifact, builder, CApi.IntPredicate.EQ, root, CApi.const_null (pointer), "foreign.retirement.null"), done, inspect);
		CApi.position_builder_at_end (builder, inspect);
		var cache = load (artifact, builder, pointer, cache_address (artifact, structs, native, builder, root, owner));
		CApi.build_cond_br (builder, compare (artifact, builder, CApi.IntPredicate.EQ, cache, CApi.const_null (pointer), "foreign.retirement.absent"), done, present);
		CApi.position_builder_at_end (builder, present);
		var layout = control_type (artifact, types, true);
		store (artifact, builder, CApi.const_null (pointer), address (artifact, builder, layout, cache, 0));
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
	}

	internal LlvmForeignClasses (LlvmModuleArtifact artifact, LlvmTypeMapper types, LlvmStructRegistry structs, LlvmClassRuntime classes, LlvmTextLowering text, SsaClass owner, NativeClassPlan plan, CAbiClassAdapter adapter, HashTable<SsaFunction, LlvmFunctionBinding> functions, HashTable<CAbiCleanupFunction, LlvmCFunctionBinding> cleanup_functions) throws LlvmError {
		this.artifact = artifact;
		this.types = types;
		this.structs = structs;
		this.classes = classes;
		this.owner = owner;
		this.plan = plan;
		this.functions = functions;
		this.adapter = adapter;
		this.cleanup_functions = cleanup_functions;
		this.text = text;
		pointer = types.scalar (NativeScalarType.PTR);
		word = types.scalar (NativeScalarType.I32);
		wide = types.scalar (NativeScalarType.U64);
		control = control_type (artifact, types, adapter.policy.declared_api != null);
		CApi.TypeRef[] fields = {
			pointer, pointer
		};
		if (adapter.policy.declared_api != null) {
			fields += wide;
		}
		weak_control = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		artifact.class_layouts.add (new LlvmClassLayoutBinding (weak_control, fields));
	}

	private void start(CAbiClassRole selected, CApi.TypeRef result, CApi.TypeRef[] parameters) throws LlvmError {
		declared_error = (CApi.ValueRef) null;
		declared_bool_parameters = null;
		declared_allocations = null;
		declared_holds = null;
		declared_held_classes = null;
		declared_held_resources = null;
		declared_provisional_class = null;
		declared_provisional_resource = null;
		if (selected < CAbiClassRole.CREATE || selected > CAbiClassRole.ATTACH || !adapter.valid () || adapter.policy.identity () != plan.foreign_export.identity () || adapter.native_class != owner.ordinal || parameters.length != CAbiClassAdapter.parameter_count (selected)) {
			throw new LlvmError.LOWERING ("opaque Class lowering lost its exact typed C ABI role");
		}
		var expected_result = CAbiClassAdapter.returns_void (selected) ? CApi.void_type_in_context (artifact.context) : CAbiClassAdapter.result (selected) == CAbiScalarType.PTR ? pointer : word;
		if ((void*) expected_result != (void*) result) {
			throw new LlvmError.LOWERING ("opaque Class role result differs from its typed C ABI plan");
		}
		for (int p = 0; p < parameters.length; p++) {
			var expected = CAbiClassAdapter.parameter (selected, p) == CAbiScalarType.PTR ? pointer : word;
			if ((void*) expected != (void*) parameters[p]) {
				throw new LlvmError.LOWERING ("opaque Class role parameter differs from its typed C ABI plan");
			}
		}
		active_symbol = adapter.symbol (selected);
		if ((void*) CApi.named_function (artifact.module, active_symbol) != null) {
			throw new LlvmError.LOWERING ("foreign Class wrapper symbol conflicts with an existing declaration: %s", active_symbol);
		}
		function_type = CApi.function_type (result, parameters, parameters.length, 0);
		function = CApi.add_function (artifact.module, active_symbol, function_type);
		CApi.set_function_call_conv (function, CApi.CallConv.C);
		CApi.set_linkage (function, CApi.Linkage.EXTERNAL);
		builder = CApi.create_builder_in_context (artifact.context);
		state = new LlvmBlockState (CApi.append_basic_block_in_context (artifact.context, function, "entry"));
		CApi.position_builder_at_end (builder, state.end);
		scalars = new LlvmScalarLowering (artifact, types, builder, function);
		allocator = new LlvmBufferAllocation (artifact, builder, function, scalars);
		shared = new LlvmSharedLowering (artifact, types, builder, function, scalars, allocator, classes, functions);
		serial = 0;
	}

	private CApi.ValueRef parameter(uint index) {
		return CApi.get_param (function, index);
	}

	private CApi.ValueRef status(uint32 code) {
		return CApi.const_int (word, code, 0);
	}

	private CApi.ValueRef empty() {
		return CApi.const_null (pointer);
	}

	private CApi.ValueRef read(CApi.ValueRef root, uint member, bool weak = false) {
		return load (artifact, builder, !weak && member == 1 ? wide : pointer, address (artifact, builder, weak ? weak_control : control, root, member));
	}

	private void write(CApi.ValueRef root, uint member, CApi.ValueRef value, bool weak = false) {
		store (artifact, builder, value, address (artifact, builder, weak ? weak_control : control, root, member));
	}

	// C ownership duties are bookkeeping for transfers. Only the native root
	// decides payload lifetime; unique roots still have no reference count.
	private CApi.ValueRef duties(CApi.ValueRef handle) throws LlvmError {
		return load (artifact, builder, wide, address (artifact, builder, control_type (artifact, types, true), handle, 5));
	}

	private ForeignImportContract resource_contract(NativeScalarOwner resource) throws LlvmError {
		foreach (var root in native_program.class_imports) {
			if (root.api.native_origin == resource.type_name && root.cleanup_symbol () == resource.cleanup_symbol && root.valid ()) {
				return root;
			}
		}
		throw new LlvmError.LOWERING ("foreign Resource lost exact declared provider root");
	}

	private LlvmCFunctionBinding resource_cleanup(NativeScalarOwner resource) throws LlvmError {
		resource_contract (resource);
		foreach (var cleanup in cleanup_functions.get_keys ()) {
			if (cleanup.external_symbol == resource.cleanup_symbol) {
				return cleanup_functions.lookup (cleanup);
			}
		}
		throw new LlvmError.LOWERING ("foreign Resource lost exact provider retirement binding");
	}

	private CApi.ValueRef resource_call(LlvmCFunctionBinding binding, CApi.ValueRef[] arguments, string name) {
		var value = CApi.build_call (builder, binding.type, binding.value, arguments, arguments.length, name);
		CApi.set_instruction_call_conv (value, CApi.CallConv.C);
		binding.record_call (value, arguments);
		return value;
	}

	private CApi.ValueRef hold_resource(CApi.ValueRef value, NativeScalarOwner resource, bool nullable) throws LlvmError {
		var root = resource_contract (resource);
		if (!nullable) {
			refuse (is_null (value), status (0x80004003U));
		}
		if (root.api.lifetime == ForeignLifetime.UNIQUE) {
			return value;
		}
		if (root.com != null || root.gobject != null) {
			var acquire = LlvmForeignImports.external (artifact, "astra_foreign16_" + root.api.prefix + "_borrow_acquire", word, new CApi.TypeRef[] { pointer });
			var status_code = resource_call (acquire, new CApi.ValueRef[] { value }, "foreign.com.borrow.acquire");
			refuse (compare (artifact, builder, CApi.IntPredicate.NE, status_code, status (0), "foreign.com.borrow.refused"), status_code);
			var release = LlvmForeignImports.external (artifact, "astra_foreign16_" + root.api.prefix + "_borrow_release", word, new CApi.TypeRef[] { pointer });
			declared_holds += value;
			declared_held_classes += null;
			declared_held_resources += release;
			return value;
		}
		var live = CApi.append_basic_block_in_context (artifact.context, function, "foreign.resource.hold.live");
		var ready = CApi.append_basic_block_in_context (artifact.context, function, "foreign.resource.hold.ready");
		CApi.build_cond_br (builder, is_null (value), ready, live);
		CApi.position_builder_at_end (builder, live);
		state.end = live;
		var acquire = LlvmForeignImports.external (artifact, root.api.prefix + "_acquire", word, new CApi.TypeRef[] { pointer });
		var count = resource_call (acquire, new CApi.ValueRef[] { value }, "foreign.resource.acquire");
		refuse (compare (artifact, builder, CApi.IntPredicate.EQ, count, status (0), "foreign.resource.acquire.refused"), status (0x8000ffffU));
		CApi.build_br (builder, ready);
		CApi.position_builder_at_end (builder, ready);
		state.end = ready;
		declared_holds += value;
		declared_held_classes += null;
		declared_held_resources += resource_cleanup (resource);
		return value;
	}

	private void change_duties(CApi.ValueRef handle, bool acquire) throws LlvmError {
		var layout = control_type (artifact, types, true);
		var place = address (artifact, builder, layout, handle, 5);
		var prior = load (artifact, builder, wide, place);
		var one = CApi.const_int (wide, 1, 0);
		var next = acquire ? CApi.build_add (builder, prior, one, "foreign.duty.acquire") : CApi.build_sub (builder, prior, one, "foreign.duty.transfer");
		artifact.class_values.add (new LlvmClassValueBinding (next, acquire ? CApi.Opcode.ADD : CApi.Opcode.SUB, wide, new CApi.ValueRef[] { prior, one }, "foreign exact C ownership duty transition"));
		store (artifact, builder, next, place);
	}

	private CApi.ValueRef owner_root(CApi.ValueRef handle, SsaClass root_class, bool nullable, CApi.ValueRef required) throws LlvmError {
		if (!nullable) {
			refuse (is_null (handle), status (0x80004003U));
		}
		var before = state.end;
		var live = CApi.append_basic_block_in_context (artifact.context, function, "foreign.owner.live");
		var done = CApi.append_basic_block_in_context (artifact.context, function, "foreign.owner.ready");
		CApi.build_cond_br (builder, is_null (handle), done, live);
		CApi.position_builder_at_end (builder, live);
		state.end = live;
		var layout = control_type (artifact, types, true);
		var context = load (artifact, builder, wide, address (artifact, builder, layout, handle, 1));
		refuse (compare (artifact, builder, CApi.IntPredicate.NE, context, thread_identity (), "foreign.owner.wrong.thread"), status (0x8001010eU));
		var root = load (artifact, builder, pointer, address (artifact, builder, layout, handle, 0));
		refuse (is_null (root), status (0x8000ffffU));
		refuse (compare (artifact, builder, CApi.IntPredicate.ULT, duties (handle), required, "foreign.owner.missing.duty"), status (0x80010001U));
		if (root_class.concurrency_policy == null) {
			refuse (compare (artifact, builder, CApi.IntPredicate.NE, load (artifact, builder, word, address (artifact, builder, layout, handle, 4)), status (0), "foreign.owner.active.borrow"), status (0x80010001U));
		}
		var admitted = state.end;
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
		var result = CApi.build_phi (builder, pointer, "foreign.owner.root");
		var zero = empty ();
		CApi.add_incoming (result, &zero, &before, 1);
		CApi.add_incoming (result, &root, &admitted, 1);
		return result;
	}

	private void validate_owner_borrows(ForeignMemberContract member, CApi.ValueRef[] handles, SsaClass?[] owner_classes) throws LlvmError {
		// Recheck after all borrowed arguments were admitted, before clearing
		// any slot. A later borrow can alias an earlier unique owner argument.
		for (uint p = 0; p < member.parameter_count; p++) {
			if (owner_classes[p] == null || owner_classes[p].concurrency_policy != null) {
				continue;
			}
			var live = CApi.append_basic_block_in_context (artifact.context, function, "foreign.owner.final.live");
			var done = CApi.append_basic_block_in_context (artifact.context, function, "foreign.owner.final.done");
			CApi.build_cond_br (builder, is_null (handles[p]), done, live);
			CApi.position_builder_at_end (builder, live);
			state.end = live;
			refuse (compare (artifact, builder, CApi.IntPredicate.NE, load (artifact, builder, word, address (artifact, builder, control_type (artifact, types, true), handles[p], 4)), status (0), "foreign.owner.final.active"), status (0x80010001U));
			CApi.build_br (builder, done);
			CApi.position_builder_at_end (builder, done);
			state.end = done;
		}
	}

	private void consume_owners(ForeignMemberContract member, CApi.ValueRef[] handles, SsaClass?[] owner_classes) throws LlvmError {
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (!channel.value_type.object_handle () || channel.transfer != ForeignTransfer.OWN) {
				continue;
			}
			store (artifact, builder, empty (), parameter (CAbiClassAdapter.declared_argument (member, p)));
			if (owner_classes[p] == null) {
				continue;
			}
			var live = CApi.append_basic_block_in_context (artifact.context, function, "foreign.owner.consume.live");
			var done = CApi.append_basic_block_in_context (artifact.context, function, "foreign.owner.consume.done");
			CApi.build_cond_br (builder, is_null (handles[p]), done, live);
			CApi.position_builder_at_end (builder, live);
			state.end = live;
			change_duties (handles[p], false);
			CApi.build_br (builder, done);
			CApi.position_builder_at_end (builder, done);
			state.end = done;
		}
	}

	private void retire_temporaries() throws LlvmError {
		if (declared_provisional_resource != null) {
			resource_call (declared_provisional_resource, new CApi.ValueRef[] { declared_provisional_root }, "");
		}
		if (declared_provisional_class != null) {
			var live = CApi.append_basic_block_in_context (artifact.context, function, "foreign.provisional.live");
			var done = CApi.append_basic_block_in_context (artifact.context, function, "foreign.provisional.done");
			CApi.build_cond_br (builder, is_null (declared_provisional_root), done, live);
			CApi.position_builder_at_end (builder, live);
			state.end = live;
			classes.release_owned (builder, function, allocator, declared_provisional_class, declared_provisional_root, state, "foreign.provisional.owner");
			CApi.build_br (builder, done);
			CApi.position_builder_at_end (builder, done);
			state.end = done;
		}
		retire_allocations ();
		retire_holds ();
	}

	private void retire_allocations() throws LlvmError {
		for (int p = declared_allocations.length - 1; p >= 0; p--) {
			allocator.deallocate (declared_allocations[p], "foreign.temporary.%d".printf (p), state);
		}
	}

	private void retire_holds() throws LlvmError {
		for (int h = declared_holds.length - 1; h >= 0; h--) {
			if (declared_held_resources[h] != null) {
				resource_call (declared_held_resources[h], new CApi.ValueRef[] { declared_holds[h] }, "");
				continue;
			}
			var held_class = declared_held_classes[h];
			var held = declared_holds[h];
			if (held_class.concurrency_policy != null) {
				shared.release_foreign (held, held_class, state);
				continue;
			}
			var live = CApi.append_basic_block_in_context (artifact.context, function, "foreign.borrow.leave.live");
			var done = CApi.append_basic_block_in_context (artifact.context, function, "foreign.borrow.leave.done");
			CApi.build_cond_br (builder, is_null (held), done, live);
			CApi.position_builder_at_end (builder, live);
			state.end = live;
			var layout = control_type (artifact, types, true);
			var place = address (artifact, builder, layout, held, 4);
			var prior = load (artifact, builder, word, place);
			var next = CApi.build_sub (builder, prior, status (1), "foreign.active.leave");
			artifact.class_values.add (new LlvmClassValueBinding (next, CApi.Opcode.SUB, word, new CApi.ValueRef[] { prior, status (1) }, "foreign exact active call retirement"));
			store (artifact, builder, next, place);
			CApi.build_br (builder, done);
			CApi.position_builder_at_end (builder, done);
			state.end = done;
		}
	}

	private CApi.ValueRef hold_root(CApi.ValueRef handle, SsaClass root_class, bool nullable) throws LlvmError {
		if (!nullable) {
			refuse (is_null (handle), status (0x80004003U));
		}
		var before = state.end;
		var live = CApi.append_basic_block_in_context (artifact.context, function, "foreign.borrow.live");
		var joined = CApi.append_basic_block_in_context (artifact.context, function, "foreign.borrow.joined");
		CApi.build_cond_br (builder, is_null (handle), joined, live);
		CApi.position_builder_at_end (builder, live);
		state.end = live;
		var layout = control_type (artifact, types, true);
		var context = load (artifact, builder, wide, address (artifact, builder, layout, handle, 1));
		refuse (compare (artifact, builder, CApi.IntPredicate.NE, context, thread_identity (), "foreign.borrow.wrong.thread"), status (0x8001010eU));
		var root = load (artifact, builder, pointer, address (artifact, builder, layout, handle, 0));
		refuse (is_null (root), status (0x8000ffffU));
		if (root_class.concurrency_policy != null) {
			shared.retain_foreign (root, state);
		} else {
			var place = address (artifact, builder, layout, handle, 4);
			var prior = load (artifact, builder, word, place);
			refuse (compare (artifact, builder, CApi.IntPredicate.EQ, prior, status (int32.MAX), "foreign.borrow.active.limit"), status (0x80010001U));
			var next = CApi.build_add (builder, prior, status (1), "foreign.borrow.active.enter");
			artifact.class_values.add (new LlvmClassValueBinding (next, CApi.Opcode.ADD, word, new CApi.ValueRef[] { prior, status (1) }, "foreign exact borrowed owner admission"));
			store (artifact, builder, next, place);
		}
		var admitted = state.end;
		CApi.build_br (builder, joined);
		CApi.position_builder_at_end (builder, joined);
		state.end = joined;
		var value = CApi.build_phi (builder, pointer, "foreign.borrow.root");
		var zero = empty ();
		CApi.add_incoming (value, &zero, &before, 1);
		CApi.add_incoming (value, &root, &admitted, 1);
		declared_holds += root_class.concurrency_policy == null ? handle : value;
		declared_held_classes += root_class;
		declared_held_resources += null;
		return value;
	}

	private void refuse(CApi.ValueRef invalid, CApi.ValueRef fallback) throws LlvmError {
		var failed = CApi.append_basic_block_in_context (artifact.context, function, "foreign.refused.%d".printf (serial++));
		var valid = CApi.append_basic_block_in_context (artifact.context, function, "foreign.admitted.%d".printf (serial++));
		CApi.build_cond_br (builder, invalid, failed, valid);
		CApi.position_builder_at_end (builder, failed);
		if ((void*) declared_error != null && (void*) fallback != null) {
			report_error (fallback);
		}
		retire_temporaries ();
		if ((void*) fallback == null) {
			CApi.build_ret_void (builder);
		} else {
			CApi.build_ret (builder, fallback);
		}
		CApi.position_builder_at_end (builder, valid);
		state.end = valid;
	}

	private CApi.ValueRef is_null(CApi.ValueRef input) {
		return compare (artifact, builder, CApi.IntPredicate.EQ, input, CApi.const_null (CApi.type_of (input)), "foreign.null");
	}

	private void finish(CApi.ValueRef result) {
		if ((void*) result == null) {
			CApi.build_ret_void (builder);
		} else {
			CApi.build_ret (builder, result);
		}
		CApi.dispose_builder (builder);
		artifact.foreign_functions.add (new LlvmForeignFunctionBinding (function, function_type, active_symbol, declared_bool_parameters));
	}

	private CApi.ValueRef native_call(SsaFunction target, CApi.ValueRef[] arguments) throws LlvmError {
		var binding = functions.lookup (target);
		if (binding == null) {
			throw new LlvmError.LOWERING ("foreign Class role lost its exact native callable binding");
		}
		var result = CApi.build_call (builder, binding.type, binding.value, arguments, arguments.length, target.return_type.kind == TypeKind.VOID ? "" : "foreign.native.result");
		CApi.set_instruction_call_conv (result, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (result, binding.value, binding.type, arguments, LlvmLowering.CALL_CONVENTION, "foreign exact native constructor/property role"));
		return result;
	}

	internal static CApi.ValueRef context_identity(LlvmModuleArtifact artifact, LlvmTypeMapper types, CApi.BuilderRef builder) throws LlvmError {
		string symbol = "astra_foreign14_thread_identity";
		var signature = CApi.function_type (types.scalar (NativeScalarType.U64), null, 0, 0);
		var target = CApi.named_function (artifact.module, symbol);
		var registered = (void*) artifact.foreign_runtime_symbols.lookup (symbol);
		if (registered == null) {
			if ((void*) target != null) {
				throw new LlvmError.LOWERING ("foreign runtime name conflicts with an existing physical declaration");
			}
			target = CApi.add_function (artifact.module, symbol, signature);
			CApi.set_function_call_conv (target, CApi.CallConv.C);
			artifact.foreign_runtime_symbols.insert (symbol, (void*) target);
		} else if ((void*) target != registered || (void*) CApi.global_value_type (target) != (void*) signature || CApi.function_call_conv (target) != CApi.CallConv.C || CApi.count_basic_blocks (target) != 0) {
			throw new LlvmError.LOWERING ("foreign thread identity lost its exact compiler-private provider ABI");
		}
		var result = CApi.build_call (builder, signature, target, null, 0, "foreign.thread.identity");
		CApi.set_instruction_call_conv (result, CApi.CallConv.C);
		CApi.ValueRef[]? arguments = null;
		artifact.class_calls.add (new LlvmClassCallBinding (result, target, signature, arguments, CApi.CallConv.C, "constructing-thread identity check"));
		return result;
	}

	private CApi.ValueRef thread_identity() throws LlvmError {
		return context_identity (artifact, types, builder);
	}

	private void require_thread(CApi.ValueRef handle, CApi.ValueRef fallback) throws LlvmError {
		refuse (compare (artifact, builder, CApi.IntPredicate.NE, read (handle, 1), thread_identity (), "foreign.wrong.thread"), fallback);
	}

	private void require_weak_thread(CApi.ValueRef handle, CApi.ValueRef fallback) throws LlvmError {
		if (adapter.policy.declared_api == null) {
			return;
		}
		var context = load (artifact, builder, wide, address (artifact, builder, weak_control, handle, 2));
		refuse (compare (artifact, builder, CApi.IntPredicate.NE, context, thread_identity (), "foreign.weak.wrong.thread"), fallback);
	}

	private CApi.ValueRef count_word(CApi.ValueRef count) throws LlvmError {
		var overflow = compare (artifact, builder, CApi.IntPredicate.UGT, count, CApi.const_int (wide, uint32.MAX, 0), "foreign.count.overflow");
		scalars.guard_slice_condition (overflow, "foreign.count.width", state);
		var result = CApi.build_trunc (builder, count, word, "foreign.count.word");
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.TRUNC, word, new CApi.ValueRef[] { count }, "foreign bounded native reference count"));
		return result;
	}

	private void emit_factory() throws LlvmError {
		start (CAbiClassRole.CREATE, pointer, new CApi.TypeRef[] { word });
		var root = allocator.allocate (status (1), structs.lookup (owner), "foreign.native.root", state, false, null, true, null, "", "object", true);
		refuse (is_null (root), empty ());
		classes.initialize (builder, owner, root, "foreign.native");
		native_call (owner.constructor, new CApi.ValueRef[] { root, parameter (0) });
		var cache = allocator.allocate (status (1), control, "foreign.control", state, false, null, false, null, "", "object", true);
		var failed = CApi.append_basic_block_in_context (artifact.context, function, "foreign.control.oom");
		var ready = CApi.append_basic_block_in_context (artifact.context, function, "foreign.control.ready");
		CApi.build_cond_br (builder, is_null (cache), failed, ready);
		CApi.position_builder_at_end (builder, failed);
		state.end = failed;
		shared.release_payload (root, owner, false, state);
		CApi.build_ret (builder, empty ());
		CApi.position_builder_at_end (builder, ready);
		state.end = ready;
		write (cache, 0, root);
		write (cache, 1, thread_identity ());
		write (cache, 2, empty ());
		write (cache, 3, empty ());
		store (artifact, builder, cache, cache_address (artifact, structs, native_program, builder, root, owner));
		finish (cache);
	}

	private NativeAbiProgram native_program;
	private void report_error(CApi.ValueRef code, int32 domain = 0) {
		var present = CApi.append_basic_block_in_context (artifact.context, function, "foreign.error.present");
		var done = CApi.append_basic_block_in_context (artifact.context, function, "foreign.error.done");
		CApi.build_cond_br (builder, is_null (declared_error), done, present);
		CApi.position_builder_at_end (builder, present);
		state.end = present;
		CApi.TypeRef[] fields = {
			word, word
		};
		var layout = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		artifact.class_layouts.add (new LlvmClassLayoutBinding (layout, fields));
		store (artifact, builder, status ((uint32) domain), address (artifact, builder, layout, declared_error, 0));
		store (artifact, builder, code, address (artifact, builder, layout, declared_error, 1));
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
	}

	private SsaClass error_class(string name) throws LlvmError {
		foreach (var plan in native_program.classes) {
			if (plan.name == name) {
				var source = classes.declaration_ordinal (plan.ordinal);
				if (source != null) {
					return source;
				}
			}
		}
		throw new LlvmError.LOWERING ("foreign error mapping lost its exact native exception declaration");
	}

	private CApi.ValueRef declared_call(SsaFunction target, CApi.ValueRef[] arguments, ForeignMemberContract member, CApi.ValueRef success) throws LlvmError {
		var value = native_call (target, arguments);
		var signature = functions.lookup (target).signature;
		if (signature.exception_plan == null) {
			return value;
		}
		if (!NativeForeignApi.errors (native_program, member, signature.exception_plan)) {
			throw new LlvmError.LOWERING ("foreign error mapping lost its checked native exception bound");
		}
		var failed = CApi.append_basic_block_in_context (artifact.context, function, "foreign.native.failed");
		var done = CApi.append_basic_block_in_context (artifact.context, function, "foreign.native.succeeded");
		CApi.build_cond_br (builder, is_null (value), done, failed);
		CApi.position_builder_at_end (builder, failed);
		state.end = failed;
		var map = member.error_map;
		var code = status ((uint32) map.at (map.case_count - 1).status);
		for (int c = (int) map.case_count - 2; c >= 0; c--) {
			var entry = map.at (c);
			var matched = classes.matches (builder, function, value, (ClassType) error_class (entry.native_origin).semantic_type, state);
			code = choose (matched, status ((uint32) entry.status), code);
		}
		classes.destroy (builder, function, value, "foreign.native.error", state, allocator, true, (ClassType) classes.declaration_ordinal (signature.exception_plan.root_ordinal).semantic_type);
		if (member.kind == ForeignMemberKind.CONSTRUCTOR) {
			classes.retire_monitor (builder, arguments[0], (ClassType) owner.semantic_type, state);
			allocator.deallocate (arguments[0], "foreign.failed.construction", state);
		}
		retire_temporaries ();
		report_error (code, map.domain);
		CApi.build_ret (builder, code);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
		return signature.has_exception_success_slot ? load (artifact, builder, types.success_result_type (signature), success) : value;
	}

	private void start_declared(string suffix, CApi.TypeRef[] parameters, uint[]? bool_parameters, bool record_bridge = false) throws LlvmError {
		declared_allocations = null;
		declared_holds = null;
		declared_held_classes = null;
		declared_held_resources = null;
		declared_provisional_class = null;
		declared_provisional_resource = null;
		if (!adapter.valid () || adapter.policy.declared_api == null || adapter.policy.identity () != plan.foreign_export.identity ()) {
			throw new LlvmError.LOWERING ("declared foreign wrapper lost its exact physical plan");
		}
		active_symbol = (record_bridge ? "astra_foreign16_" : "") + adapter.policy.prefix + "_" + suffix;
		if ((void*) CApi.named_function (artifact.module, active_symbol) != null) {
			throw new LlvmError.LOWERING ("declared foreign wrapper symbol collision: %s", active_symbol);
		}
		function_type = CApi.function_type (word, parameters, parameters.length, 0);
		function = CApi.add_function (artifact.module, active_symbol, function_type);
		CApi.set_function_call_conv (function, CApi.CallConv.C);
		CApi.set_linkage (function, CApi.Linkage.EXTERNAL);
		declared_bool_parameters = bool_parameters.copy ();
		foreach (uint parameter in bool_parameters) {
			CApi.add_attribute (function, parameter, CApi.create_enum_attribute (artifact.context, CApi.enum_attribute_kind ("zeroext", 7), 0));
		}
		builder = CApi.create_builder_in_context (artifact.context);
		state = new LlvmBlockState (CApi.append_basic_block_in_context (artifact.context, function, "entry"));
		CApi.position_builder_at_end (builder, state.end);
		scalars = new LlvmScalarLowering (artifact, types, builder, function);
		allocator = new LlvmBufferAllocation (artifact, builder, function, scalars);
		shared = new LlvmSharedLowering (artifact, types, builder, function, scalars, allocator, classes, functions);
		serial = 0;
		declared_error = parameter ((uint) parameters.length - 1);
		report_error (status (0));
	}

	private CApi.ValueRef boolean_and(CApi.ValueRef left, CApi.ValueRef right) throws LlvmError {
		var result = CApi.build_and (builder, left, right, "foreign.both");
		if ((void*) CApi.is_instruction (result) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.AND, types.scalar (NativeScalarType.B1), new CApi.ValueRef[] { left, right }, "foreign complete pointer/count guard"));
		}
		return result;
	}

	private void copy_bytes(CApi.ValueRef destination, CApi.ValueRef source, CApi.ValueRef count) {
		var extent = CApi.build_zext (builder, count, wide, "foreign.copy.extent");
		if ((void*) CApi.is_instruction (extent) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (extent, CApi.Opcode.ZEXT, wide, new CApi.ValueRef[] { count }, "foreign validated byte count"));
		}
		uint identity = CApi.lookup_intrinsic_id ("llvm.memcpy", 11);
		CApi.TypeRef[] overloads = {
			pointer, pointer, wide
		};
		var target = CApi.get_intrinsic_declaration (artifact.module, identity, overloads, overloads.length);
		var signature = CApi.intrinsic_get_type (artifact.context, identity, overloads, overloads.length);
		CApi.ValueRef[] arguments = {
			destination, source, extent, CApi.const_null (CApi.int1_type_in_context (artifact.context))
		};
		var call = CApi.build_call (builder, signature, target, arguments, arguments.length, "");
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (call, target, signature, arguments, CApi.CallConv.C, "foreign exact initialized byte copy"));
	}

	private CApi.ValueRef extract(CApi.ValueRef value, uint member, CApi.TypeRef type) {
		var result = CApi.build_extract_value (builder, value, member, "foreign.result.part");
		artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.EXTRACT_VALUE, type, new CApi.ValueRef[] { value }, "foreign complete native result pair", (int) member));
		return result;
	}

	private CApi.ValueRef choose(CApi.ValueRef condition, CApi.ValueRef yes, CApi.ValueRef no) {
		var result = CApi.build_select (builder, condition, yes, no, "foreign.selected");
		if ((void*) CApi.is_instruction (result) != null) {
			artifact.class_values.add (new LlvmClassValueBinding (result, CApi.Opcode.SELECT, CApi.type_of (yes), new CApi.ValueRef[] { condition, yes, no }, "foreign exact empty representation"));
		}
		return result;
	}

	private CApi.TypeRef record_type(ForeignValueType declaration) throws LlvmError {
		if (!declaration.valid () || declaration.kind != ForeignValueKind.RECORD) {
			throw new LlvmError.LOWERING ("foreign record storage requires a valid scalar POD declaration");
		}
		string key = declaration.identity ();
		var existing = (CApi.TypeRef) record_types.lookup (key);
		if ((void*) existing != null) {
			return existing;
		}
		var storage = LlvmForeignRecordLayoutBinding.storage_type (artifact, types, declaration);
		record_types.insert (key, (void*) storage);
		return storage;
	}

	private void clear_record(CApi.ValueRef destination, ForeignValueType declaration) throws LlvmError {
		record_type (declaration);
		uint identity = CApi.lookup_intrinsic_id ("llvm.memset", 11);
		CApi.TypeRef[] overloads = {
			pointer, wide
		};
		var target = CApi.get_intrinsic_declaration (artifact.module, identity, overloads, overloads.length);
		var signature = CApi.intrinsic_get_type (artifact.context, identity, overloads, overloads.length);
		CApi.ValueRef[] arguments = {
			destination, CApi.const_null (types.scalar (NativeScalarType.U8)), CApi.const_int (wide, CAbiClassAdapter.record_size (declaration), 0), CApi.const_null (CApi.int1_type_in_context (artifact.context))
		};
		var call = CApi.build_call (builder, signature, target, arguments, arguments.length, "");
		CApi.set_instruction_call_conv (call, CApi.CallConv.C);
		artifact.class_calls.add (new LlvmClassCallBinding (call, target, signature, arguments, CApi.CallConv.C, "foreign exact POD output initialization including padding"));
	}

	private void initialize_declared_wrapper(CApi.ValueRef cache, CApi.ValueRef root, SsaClass root_class) throws LlvmError {
		var layout = control_type (artifact, types, true);
		store (artifact, builder, root, address (artifact, builder, layout, cache, 0));
		var context = load (artifact, builder, wide, root_context_address (artifact, structs, native_program, builder, root, root_class));
		store (artifact, builder, context, address (artifact, builder, layout, cache, 1));
		store (artifact, builder, empty (), address (artifact, builder, layout, cache, 2));
		store (artifact, builder, empty (), address (artifact, builder, layout, cache, 3));
		store (artifact, builder, status (0), address (artifact, builder, layout, cache, 4));
		store (artifact, builder, CApi.const_null (wide), address (artifact, builder, layout, cache, 5));
	}

	private CApi.ValueRef owned_wrapper(CApi.ValueRef root, SsaClass root_class, bool nullable) throws LlvmError {
		if (!nullable) {
			refuse (is_null (root), status (0x8000ffffU));
		}
		var before = state.end;
		var live = CApi.append_basic_block_in_context (artifact.context, function, "foreign.result.live");
		var done = CApi.append_basic_block_in_context (artifact.context, function, "foreign.result.joined");
		CApi.build_cond_br (builder, is_null (root), done, live);
		CApi.position_builder_at_end (builder, live);
		state.end = live;
		var cache_place = cache_address (artifact, structs, native_program, builder, root, root_class);
		var prior = load (artifact, builder, pointer, cache_place);
		var create = CApi.append_basic_block_in_context (artifact.context, function, "foreign.result.wrap");
		var ready = CApi.append_basic_block_in_context (artifact.context, function, "foreign.result.ready");
		var reuse = CApi.append_basic_block_in_context (artifact.context, function, "foreign.result.reuse");
		CApi.build_cond_br (builder, is_null (prior), create, reuse);
		CApi.position_builder_at_end (builder, reuse);
		state.end = reuse;
		CApi.build_br (builder, ready);
		CApi.position_builder_at_end (builder, create);
		state.end = create;
		var cache = allocator.allocate (status (1), control_type (artifact, types, true), "foreign.result.control", state, false, null, false, null, "", "object", true);
		var failed = CApi.append_basic_block_in_context (artifact.context, function, "foreign.result.oom");
		var publish = CApi.append_basic_block_in_context (artifact.context, function, "foreign.result.publish");
		CApi.build_cond_br (builder, is_null (cache), failed, publish);
		CApi.position_builder_at_end (builder, failed);
		state.end = failed;
		retire_temporaries ();
		report_error (status (0x8007000eU));
		CApi.build_ret (builder, status (0x8007000eU));
		CApi.position_builder_at_end (builder, publish);
		state.end = publish;
		initialize_declared_wrapper (cache, root, root_class);
		store (artifact, builder, cache, cache_place);
		var published = state.end;
		CApi.build_br (builder, ready);
		CApi.position_builder_at_end (builder, ready);
		state.end = ready;
		var selected = CApi.build_phi (builder, pointer, "foreign.result.wrapper");
		CApi.add_incoming (selected, &prior, &reuse, 1);
		CApi.add_incoming (selected, &cache, &published, 1);
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
		var result = CApi.build_phi (builder, pointer, "foreign.result.handle");
		var zero = empty ();
		CApi.add_incoming (result, &zero, &before, 1);
		CApi.add_incoming (result, &selected, &ready, 1);
		return result;
	}

	private void publish_owner(CApi.ValueRef handle, CApi.ValueRef destination) throws LlvmError {
		var live = CApi.append_basic_block_in_context (artifact.context, function, "foreign.owner.publish.live");
		var done = CApi.append_basic_block_in_context (artifact.context, function, "foreign.owner.publish.done");
		CApi.build_cond_br (builder, is_null (handle), done, live);
		CApi.position_builder_at_end (builder, live);
		state.end = live;
		change_duties (handle, true);
		CApi.build_br (builder, done);
		CApi.position_builder_at_end (builder, done);
		state.end = done;
		store (artifact, builder, handle, destination);
	}

	private void publish_parameters(ForeignMemberContract member, CApi.ValueRef[] scalar_scratch, CApi.ValueRef[] byte_scratch, CApi.ValueRef[] produced_counts) throws LlvmError {
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (channel.by_reference && channel.direction != ForeignDirection.IN) {
				store (artifact, builder, load (artifact, builder, types.scalar (NativeForeignApi.scalar (channel.value_type.kind)), scalar_scratch[p]), parameter (CAbiClassAdapter.declared_argument (member, p)));
			}
			if (channel.value_type.kind == ForeignValueKind.BYTES && channel.direction != ForeignDirection.IN) {
				copy_bytes (parameter (CAbiClassAdapter.declared_argument (member, p)), byte_scratch[p], produced_counts[p]);
			}
		}
	}

	private void emit_declared_member(uint ordinal) throws LlvmError {
		var api = adapter.policy.declared_api;
		var member = api.member (ordinal);
		var target = SsaForeignApi.target (owner, member);
		if (target == null || plan.foreign_member (ordinal) != adapter.member_target (ordinal) || plan.foreign_member (ordinal) != target.ordinal) {
			throw new LlvmError.LOWERING ("declared foreign member lost its actual native target");
		}
		bool factory = member.kind == ForeignMemberKind.CONSTRUCTOR;
		bool result = member.result.value_type.kind != ForeignValueKind.VOID;
		bool buffer_result = member.result.value_type.kind == ForeignValueKind.BYTES;
		bool text_result = member.result.value_type.kind == ForeignValueKind.TEXT;
		bool record_result = member.result.value_type.kind == ForeignValueKind.RECORD;
		bool object_result = !factory && member.result.value_type.object_handle ();
		bool sequence_result = buffer_result || text_result;
		var parameters = new CApi.TypeRef[CAbiClassAdapter.declared_result (member) + CAbiClassAdapter.declared_result_width (member) + 1];
		uint[] bool_parameters = null;
		if (!factory) {
			parameters[0] = pointer;
		}
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			uint position = CAbiClassAdapter.declared_argument (member, p);
			if (channel.by_reference) {
				parameters[position] = pointer;
			} else if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
				parameters[position] = pointer;
				parameters[position + 1] = pointer;
			} else if (channel.value_type.kind == ForeignValueKind.RECORD) {
				record_type (channel.value_type);
				parameters[position] = pointer;
			} else if (channel.value_type.object_handle ()) {
				parameters[position] = pointer;
			} else if (CAbiClassAdapter.byte_sequence (channel.value_type.kind)) {
				parameters[position] = pointer;
				if (channel.intrinsic_length) {
					parameters[position + 1] = word;
				}
			} else {
				parameters[position] = types.scalar (NativeForeignApi.scalar (channel.value_type.kind));
			}
			if (!channel.by_reference && channel.value_type.kind == ForeignValueKind.BOOL) {
				bool_parameters += position + 1;
			}
		}
		uint out_index = CAbiClassAdapter.declared_result (member);
		if (result) {
			parameters[out_index] = pointer;
		}
		if (sequence_result) {
			parameters[out_index + 1] = pointer;
		}
		parameters[parameters.length - 1] = pointer;
		start_declared (member.name, parameters, bool_parameters, CAbiClassAdapter.record_forwarder (member));
		// Slots must be distinct before any output initialization or transfer.
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (!channel.value_type.object_handle () || channel.transfer != ForeignTransfer.OWN) {
				continue;
			}
			var slot = parameter (CAbiClassAdapter.declared_argument (member, p));
			refuse (is_null (slot), status (0x80004003U));
			if (result) {
				refuse (compare (artifact, builder, CApi.IntPredicate.EQ, slot, parameter (out_index), "foreign.owner.output.alias"), status (0x80070057U));
			}
			for (uint q = 0; q < p; q++) {
				var previous = member.parameter (q);
				if (previous.value_type.object_handle () && previous.transfer == ForeignTransfer.OWN) {
					refuse (compare (artifact, builder, CApi.IntPredicate.EQ, slot, parameter (CAbiClassAdapter.declared_argument (member, q)), "foreign.owner.slot.alias"), status (0x80070057U));
				}
			}
		}
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (!channel.by_reference || !result) {
				continue;
			}
			refuse (compare (artifact, builder, CApi.IntPredicate.EQ, parameter (CAbiClassAdapter.declared_argument (member, p)), parameter (out_index), "foreign.scalar.result.alias"), status (0x80070057U));
		}
		if (result) {
			refuse (is_null (parameter ((uint) out_index)), status (0x80004003U));
			if (sequence_result) {
				refuse (is_null (parameter (out_index + 1)), status (0x80004003U));
				store (artifact, builder, status (0), parameter (out_index + 1));
			}
			if (record_result) {
				clear_record (parameter (out_index), member.result.value_type);
			} else {
				store (artifact, builder, factory || sequence_result || object_result ? empty () : CApi.const_null (types.scalar (NativeForeignApi.scalar (member.result.value_type.kind))), parameter ((uint) out_index));
			}
		}
		var scalar_scratch = new CApi.ValueRef[member.parameter_count];
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (!channel.by_reference) {
				continue;
			}
			var place = parameter (CAbiClassAdapter.declared_argument (member, p));
			refuse (is_null (place), status (0x80004003U));
			var scalar_type = types.scalar (NativeForeignApi.scalar (channel.value_type.kind));
			var scratch = CApi.build_alloca (builder, scalar_type, "foreign.scalar.scratch");
			scalar_scratch[p] = scratch;
			store (artifact, builder, channel.direction == ForeignDirection.OUT ? CApi.const_null (scalar_type) : load (artifact, builder, scalar_type, place), scratch);
		}
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (channel.by_reference && channel.direction == ForeignDirection.OUT) {
				store (artifact, builder, CApi.const_null (types.scalar (NativeForeignApi.scalar (channel.value_type.kind))), parameter (CAbiClassAdapter.declared_argument (member, p)));
			}
		}
		if (!factory) {
			refuse (is_null (parameter (0)), status (0x80004003U));
			require_thread (parameter (0), status (0x8001010eU));
		}
		var byte_counts = new CApi.ValueRef[member.parameter_count];
		for (uint p = 0; p < member.parameter_count; p++) {
			if (member.parameter (p).value_type.kind == ForeignValueKind.RECORD) {
				refuse (is_null (parameter (CAbiClassAdapter.declared_argument (member, p))), status (0x80004003U));
			}
			if (member.parameter (p).value_type.kind == ForeignValueKind.CALLBACK && !member.parameter (p).nullable) {
				refuse (is_null (parameter (CAbiClassAdapter.declared_argument (member, p))), status (0x80004003U));
			}
			var channel = member.parameter (p);
			if (!CAbiClassAdapter.byte_sequence (channel.value_type.kind)) {
				continue;
			}
			var data = parameter (CAbiClassAdapter.declared_argument (member, p));
			CApi.ValueRef count;
			if (channel.encoding == ForeignTextEncoding.UTF8_NUL) {
				if (!channel.nullable) {
					refuse (is_null (data), status (0x80004003U));
				}
				count = choose (is_null (data), status (0), text.find_nul (builder, data, status (int32.MAX)));
			} else {
				count = parameter (CAbiClassAdapter.declared_count (member, p));
			}
			byte_counts[p] = count;
			refuse (compare (artifact, builder, CApi.IntPredicate.SLT, count, status (0), "foreign.negative.count"), status (0x80070057U));
			var absent = is_null (data);
			if (channel.nullable) {
				absent = boolean_and (absent, compare (artifact, builder, CApi.IntPredicate.NE, count, status (0), "foreign.nonempty.count"));
			}
			refuse (absent, status (0x80004003U));
		}
		CApi.ValueRef receiver = (CApi.ValueRef) null;
		if (!factory) {
			receiver = hold_root (parameter (0), owner, false);
		}
		var object_roots = new CApi.ValueRef[member.parameter_count];
		var owner_handles = new CApi.ValueRef[member.parameter_count];
		var owner_classes = new SsaClass?[member.parameter_count];
		var resource_roots = new ForeignImportContract?[member.parameter_count];
		uint native_parameter = 0;
		var signature = functions.lookup (target).signature;
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (channel.value_type.object_handle ()) {
				var actual = signature.parameters[native_parameter];
				if (actual.resource != null) {
					resource_roots[p] = resource_contract (actual.resource);
					var argument = parameter (CAbiClassAdapter.declared_argument (member, p));
					if (channel.transfer == ForeignTransfer.BORROW) {
						object_roots[p] = hold_resource (argument, actual.resource, channel.nullable);
					} else {
						var value = load (artifact, builder, pointer, argument);
						if (!channel.nullable) {
							refuse (is_null (value), status (0x80004003U));
						}
						owner_handles[p] = value;
						object_roots[p] = value;
					}
					native_parameter++;
					continue;
				}
				var root_class = classes.declaration_ordinal (channel.transfer == ForeignTransfer.BORROW ? actual.borrowed_class_ordinal : actual.object_origin.class_ordinal);
				if (root_class == null) {
					throw new LlvmError.LOWERING ("native object borrow lost its exact nominal class plan");
				}
				var argument = parameter (CAbiClassAdapter.declared_argument (member, p));
				if (channel.transfer == ForeignTransfer.BORROW) {
					object_roots[p] = hold_root (argument, root_class, channel.nullable);
				} else {
					var handle = load (artifact, builder, pointer, argument);
					owner_handles[p] = handle;
					owner_classes[p] = root_class;
					var required = CApi.const_int (wide, 1, 0);
					for (uint q = 0; q < p; q++) {
						var previous = member.parameter (q);
						if (!previous.value_type.object_handle () || previous.transfer != ForeignTransfer.OWN) {
							continue;
						}
						var equal = compare (artifact, builder, CApi.IntPredicate.EQ, handle, owner_handles[q], "foreign.owner.same.root");
						var extra = choose (equal, CApi.const_int (wide, 1, 0), CApi.const_null (wide));
						var sum = CApi.build_add (builder, required, extra, "foreign.owner.required.duties");
						artifact.class_values.add (new LlvmClassValueBinding (sum, CApi.Opcode.ADD, wide, new CApi.ValueRef[] { required, extra }, "foreign exact duplicate owner duty requirement"));
						required = sum;
					}
					object_roots[p] = owner_root (handle, root_class, channel.nullable, required);
				}
			}
			native_parameter += channel.value_type.kind == ForeignValueKind.RECORD ? channel.value_type.field_count : 1;
		}
		for (uint p = 0; p < member.parameter_count; p++) {
			var root = resource_roots[p];
			if (root == null || root.api.lifetime != ForeignLifetime.UNIQUE || member.parameter (p).transfer != ForeignTransfer.OWN) {
				continue;
			}
			for (uint q = 0; q < member.parameter_count; q++) {
				if (q == p || resource_roots[q] == null || resource_roots[q].api.native_origin != root.api.native_origin || member.parameter (q).transfer == ForeignTransfer.OWN && q > p) {
					continue;
				}
				var alias = boolean_and (compare (artifact, builder, CApi.IntPredicate.EQ, owner_handles[p], object_roots[q], "foreign.resource.unique.alias"), compare (artifact, builder, CApi.IntPredicate.NE, owner_handles[p], empty (), "foreign.resource.unique.live"));
				refuse (alias, status (0x80010001U));
			}
		}
		validate_owner_borrows (member, owner_handles, owner_classes);
		var arguments = new CApi.ValueRef[functions.lookup (target).signature.physical_parameter_count];
		CApi.ValueRef success = (CApi.ValueRef) null;
		var byte_scratch = new CApi.ValueRef[member.parameter_count];
		uint component = 1;
		if (signature.has_exception_success_slot) {
			success = CApi.build_alloca (builder, types.success_result_type (signature), "foreign.native.success");
			arguments[component++] = success;
		}
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			uint position = CAbiClassAdapter.declared_argument (member, p);
			if (channel.by_reference) {
				arguments[component++] = scalar_scratch[p];
				continue;
			}
			if (channel.value_type.kind == ForeignValueKind.CALLBACK) {
				arguments[component++] = new LlvmCallbackRuntime (artifact, types).from_c (builder, channel.value_type, parameter (position), parameter (position + 1), channel.nullable);
				continue;
			}
			if (channel.value_type.object_handle ()) {
				arguments[component++] = object_roots[p];
				continue;
			}
			if (channel.value_type.kind == ForeignValueKind.RECORD) {
				var storage = record_type (channel.value_type);
				for (uint f = 0; f < channel.value_type.field_count; f++) {
					arguments[component++] = load (artifact, builder, types.scalar (NativeForeignApi.scalar (channel.value_type.field (f).kind)), address (artifact, builder, storage, parameter (position), f));
				}
				continue;
			}
			if (!CAbiClassAdapter.byte_sequence (channel.value_type.kind)) {
				arguments[component++] = parameter (position);
				continue;
			}
			var count = byte_counts[p];
			var scratch = allocator.allocate (count, types.scalar (NativeScalarType.U8), "foreign.bytes.%u".printf (p), state, false, null, false, null, "", "buffer", true);
			refuse (boolean_and (is_null (scratch), compare (artifact, builder, CApi.IntPredicate.NE, count, status (0), "foreign.allocation.required")), status (0x8007000eU));
			declared_allocations += scratch;
			byte_scratch[p] = scratch;
			if (channel.direction != ForeignDirection.OUT) {
				copy_bytes (scratch, parameter (position), count);
			}
			if (channel.value_type.kind == ForeignValueKind.TEXT) {
				refuse (compare (artifact, builder, CApi.IntPredicate.EQ, text.validate_counted_utf8 (builder, scratch, count), CApi.const_null (CApi.int1_type_in_context (artifact.context)), "foreign.invalid.utf8"), status (0x80070459U));
			}
			arguments[component++] = scratch;
			arguments[component++] = count;
		}
		if (component != arguments.length) {
			throw new LlvmError.LOWERING ("declared foreign call lost its complete physical argument grouping");
		}
		CApi.ValueRef value;
		SsaClass? result_class = null;
		if (factory) {
			var root = allocator.allocate (status (1), structs.lookup (owner), "foreign.native.root", state, false, null, true, null, "", "object", true);
			refuse (is_null (root), status (0x8007000eU));
			classes.initialize (builder, owner, root, "foreign.native");
			consume_owners (member, owner_handles, owner_classes);
			arguments[0] = root;
			declared_call (target, arguments, member, success);
			value = root;
			result_class = owner;
		} else {
			arguments[0] = receiver;
			consume_owners (member, owner_handles, owner_classes);
			value = declared_call (target, arguments, member, success);
			if (object_result && signature.resource_result == null) {
				result_class = classes.declaration_ordinal (signature.heap_result.class_ordinal);
				if (result_class == null) {
					throw new LlvmError.LOWERING ("owned native result lost its exact class plan");
				}
			}
		}
		if (result_class != null) {
			declared_provisional_root = value;
			declared_provisional_class = result_class;
		}
		if (object_result && signature.resource_result != null) {
			declared_provisional_root = value;
			declared_provisional_resource = resource_cleanup (signature.resource_result);
			if (!member.result.nullable) {
				refuse (is_null (value), status (0x8000ffffU));
			}
		}
		var produced_counts = new CApi.ValueRef[member.parameter_count];
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (channel.value_type.kind != ForeignValueKind.BYTES || channel.direction == ForeignDirection.IN) {
				continue;
			}
			var count = channel.produced_by_result ? value : load (artifact, builder, word, scalar_scratch[channel.produced_index]);
			produced_counts[p] = count;
			refuse (compare (artifact, builder, CApi.IntPredicate.SLT, count, status (0), "foreign.negative.produced"), status (0x8000ffffU));
			refuse (compare (artifact, builder, CApi.IntPredicate.SGT, count, parameter (CAbiClassAdapter.declared_count (member, p)), "foreign.excess.produced"), status (0x8000ffffU));
		}
		if (object_result && signature.resource_result != null) {
			declared_provisional_resource = null;
			retire_holds ();
			publish_parameters (member, scalar_scratch, byte_scratch, produced_counts);
			store (artifact, builder, value, parameter (out_index));
			retire_allocations ();
			finish (member.null_status == 0 ? status (0) : choose (is_null (value), status ((uint32) member.null_status), status (0)));
			return;
		}
		if (factory || object_result) {
			var handle = owned_wrapper (value, result_class, member.result.nullable);
			declared_provisional_class = null;
			retire_holds ();
			publish_parameters (member, scalar_scratch, byte_scratch, produced_counts);
			publish_owner (handle, parameter (out_index));
			retire_allocations ();
			finish (member.null_status == 0 ? status (0) : choose (is_null (handle), status ((uint32) member.null_status), status (0)));
			return;
		}
		CApi.ValueRef result_data = (CApi.ValueRef) null, result_length = (CApi.ValueRef) null;
		if (sequence_result) {
			var data = extract (value, 0, pointer);
			var length = extract (value, 1, word);
			var zero_length = compare (artifact, builder, CApi.IntPredicate.EQ, length, status (0), "foreign.result.empty");
			if (text_result) {
				var extent = choose (zero_length, status (1), length);
				if (member.result.encoding == ForeignTextEncoding.UTF8_NUL) {
					refuse (compare (artifact, builder, CApi.IntPredicate.SGE, text.find_nul (builder, data, length), status (0), "foreign.embedded.nul"), status (0x80070057U));
					refuse (compare (artifact, builder, CApi.IntPredicate.EQ, length, status (int32.MAX), "foreign.nul.extent"), status (0x80070057U));
					extent = CApi.build_add (builder, length, status (1), "foreign.terminated.extent");
					artifact.class_values.add (new LlvmClassValueBinding (extent, CApi.Opcode.ADD, word, new CApi.ValueRef[] { length, status (1) }, "foreign exact NUL sentinel extent"));
				}
				var snapshot = allocator.allocate (extent, types.scalar (NativeScalarType.U8), "foreign.text.snapshot", state, false, null, false, null, "", "buffer", true);
				refuse (is_null (snapshot), status (0x8007000eU));
				copy_bytes (snapshot, data, length);
				data = snapshot;
			} else {
				declared_allocations += data;
				var empty_owner = allocator.allocate (choose (zero_length, status (1), status (0)), types.scalar (NativeScalarType.U8), "foreign.bytes.empty", state, false, null, false, null, "", "buffer", true);
				refuse (boolean_and (zero_length, is_null (empty_owner)), status (0x8007000eU));
				declared_allocations.resize (declared_allocations.length - 1);
				var retire = CApi.append_basic_block_in_context (artifact.context, function, "foreign.empty.retire");
				var ready = CApi.append_basic_block_in_context (artifact.context, function, "foreign.empty.ready");
				CApi.build_cond_br (builder, zero_length, retire, ready);
				CApi.position_builder_at_end (builder, retire);
				state.end = retire;
				allocator.deallocate (data, "foreign.native.empty", state);
				CApi.build_br (builder, ready);
				CApi.position_builder_at_end (builder, ready);
				state.end = ready;
				data = choose (zero_length, empty_owner, data);
			}
			result_data = data;
			result_length = length;
		}
		retire_holds ();
		publish_parameters (member, scalar_scratch, byte_scratch, produced_counts);
		if (sequence_result) {
			store (artifact, builder, result_data, parameter (out_index));
			store (artifact, builder, result_length, parameter (out_index + 1));
		} else if (record_result) {
			var declaration = member.result.value_type;
			var storage = record_type (declaration);
			for (uint f = 0; f < declaration.field_count; f++) {
				var field = declaration.field (f);
				var field_type = types.scalar (NativeForeignApi.scalar (field.kind));
				var leaf = declaration.field_count == 1 ? value : extract (value, f, field_type);
				store (artifact, builder, leaf, address (artifact, builder, storage, parameter (out_index), f));
			}
		} else if (result) {
			store (artifact, builder, value, parameter ((uint) out_index));
		}
		retire_allocations ();
		finish (status (0));
	}

	private void emit_declared() throws LlvmError {
		var api = adapter.policy.declared_api;
		for (uint m = 0; m < api.member_count; m++) {
			emit_declared_member (m);
		}
		if (api.lifetime == ForeignLifetime.SHARED && adapter.policy.active (ForeignClassPolicy.GOBJECT)) {
			start_declared ("native_project", new CApi.TypeRef[] { pointer, pointer, pointer }, null, true);
			refuse (is_null (parameter (1)), status (0x80004003U));
			store (artifact, builder, empty (), parameter (1));
			var root = parameter (0);
			refuse (is_null (root), status (0));
			var context = load (artifact, builder, wide, root_context_address (artifact, structs, native_program, builder, root, owner));
			refuse (compare (artifact, builder, CApi.IntPredicate.NE, context, thread_identity (), "foreign.projection.wrong.thread"), status (0x8001010eU));
			var handle = owned_wrapper (root, owner, false);
			refuse (compare (artifact, builder, CApi.IntPredicate.EQ, duties (handle), CApi.const_int (wide, uint64.MAX, 0), "foreign.projection.duty.limit"), status (0x8007000eU));
			shared.retain_foreign (root, state);
			publish_owner (handle, parameter (1));
			finish (status (0));
		}
		foreach (var kind in new ForeignValueKind[] { ForeignValueKind.BYTES, ForeignValueKind.TEXT }) {
			bool found = false;
			for (uint m = 0; m < api.member_count; m++) {
				found |= api.member (m).result.value_type.kind == kind;
			}
			if (!found) {
				continue;
			}
			start_declared (kind == ForeignValueKind.BYTES ? "bytes_release" : "text_release", new CApi.TypeRef[] { pointer, pointer, pointer }, null);
			refuse (is_null (parameter (0)), status (0x80004003U));
			refuse (is_null (parameter (1)), status (0x80004003U));
			var bytes = load (artifact, builder, pointer, parameter (0));
			store (artifact, builder, empty (), parameter (0));
			store (artifact, builder, status (0), parameter (1));
			allocator.deallocate (bytes, "foreign.result.release", state);
			finish (status (0));
		}
		if (api.lifetime == ForeignLifetime.UNIQUE) {
			start_declared ("destroy", new CApi.TypeRef[] { pointer, pointer }, null);
			refuse (is_null (parameter (0)), status (0x80004003U));
			var handle = load (artifact, builder, pointer, parameter (0));
			refuse (is_null (handle), status (0));
			require_thread (handle, status (0x8001010eU));
			refuse (compare (artifact, builder, CApi.IntPredicate.NE, load (artifact, builder, word, address (artifact, builder, control, handle, 4)), status (0), "foreign.active.owner"), status (0x80010001U));
			refuse (compare (artifact, builder, CApi.IntPredicate.NE, duties (handle), CApi.const_int (wide, 1, 0), "foreign.unique.transferred"), status (0x80010001U));
			var root = read (handle, 0);
			refuse (is_null (root), status (0x8000ffffU));
			store (artifact, builder, empty (), parameter (0));
			change_duties (handle, false);
			classes.release_owned (builder, function, allocator, owner, root, state, "foreign.unique");
			finish (status (0));
		} else {
			emit_counts ();
			emit_weak ();
		}
		start (CAbiClassRole.ROOT_IDENTITY, pointer, new CApi.TypeRef[] { pointer });
		refuse (is_null (parameter (0)), empty ());
		finish (read (parameter (0), 0));
		emit_personality ();
	}

	private void emit_counts() throws LlvmError {
		start (CAbiClassRole.ACQUIRE, word, new CApi.TypeRef[] { pointer });
		refuse (is_null (parameter (0)), status (0));
		if (adapter.policy.declared_api != null) {
			require_thread (parameter (0), status (0));
			refuse (is_null (read (parameter (0), 0)), status (0));
			refuse (compare (artifact, builder, CApi.IntPredicate.EQ, duties (parameter (0)), CApi.const_int (wide, uint64.MAX, 0), "foreign.duty.limit"), status (0));
			change_duties (parameter (0), true);
		}
		finish (count_word (shared.retain_foreign (read (parameter (0), 0), state)));
		start (CAbiClassRole.RELEASE, word, new CApi.TypeRef[] { pointer });
		refuse (is_null (parameter (0)), status (0));
		if (adapter.policy.declared_api != null) {
			require_thread (parameter (0), status (0));
			refuse (is_null (read (parameter (0), 0)), status (0));
			refuse (compare (artifact, builder, CApi.IntPredicate.EQ, duties (parameter (0)), CApi.const_null (wide), "foreign.duty.empty"), status (0));
			change_duties (parameter (0), false);
		}
		finish (count_word (shared.release_foreign (read (parameter (0), 0), owner, state)));
	}

	private void emit_properties() throws LlvmError {
		var property = owner.properties[plan.foreign_export.property_ordinal];
		start (CAbiClassRole.GET, word, new CApi.TypeRef[] { pointer, pointer });
		refuse (is_null (parameter (1)), status (0x80004003U));
		store (artifact, builder, status (0), parameter (1));
		refuse (is_null (parameter (0)), status (0x80004003U));
		require_thread (parameter (0), status (0x8001010eU));
		var value = native_call (property.getter, new CApi.ValueRef[] { read (parameter (0), 0) });
		store (artifact, builder, value, parameter (1));
		finish (status (0));
		start (CAbiClassRole.SET, word, new CApi.TypeRef[] { pointer, word });
		refuse (is_null (parameter (0)), status (0x80004003U));
		require_thread (parameter (0), status (0x8001010eU));
		native_call (property.setter, new CApi.ValueRef[] { read (parameter (0), 0), parameter (1) });
		finish (status (0));
		start (CAbiClassRole.ROOT_IDENTITY, pointer, new CApi.TypeRef[] { pointer });
		refuse (is_null (parameter (0)), empty ());
		finish (read (parameter (0), 0));
	}

	private void emit_personality() throws LlvmError {
		start (CAbiClassRole.CHECK_THREAD, word, new CApi.TypeRef[] { pointer });
		refuse (is_null (parameter (0)), status (0x80004003U));
		require_thread (parameter (0), status (0x8001010eU));
		finish (status (0));
		start (CAbiClassRole.PERSONALITY, pointer, new CApi.TypeRef[] { pointer });
		refuse (is_null (parameter (0)), empty ());
		require_thread (parameter (0), empty ());
		finish (read (parameter (0), 2));
		start (CAbiClassRole.ATTACH, word, new CApi.TypeRef[] { pointer, pointer, pointer });
		refuse (is_null (parameter (0)), status (0x80004003U));
		require_thread (parameter (0), status (0x8001010eU));
		refuse (is_null (parameter (1)), status (0x80004003U));
		refuse (compare (artifact, builder, CApi.IntPredicate.NE, read (parameter (0), 2), empty (), "foreign.personality.already.bound"), status (0x8000ffffU));
		write (parameter (0), 2, parameter (1));
		write (parameter (0), 3, parameter (2));
		finish (status (0));
	}

	private void emit_weak() throws LlvmError {
		start (CAbiClassRole.WEAK, pointer, new CApi.TypeRef[] { pointer });
		refuse (is_null (parameter (0)), empty ());
		if (adapter.policy.declared_api != null) {
			require_thread (parameter (0), empty ());
			refuse (is_null (read (parameter (0), 0)), empty ());
		}
		var weak_wrapper = allocator.allocate (status (1), weak_control, "foreign.weak", state, false, null, false, null, "", "object", true);
		refuse (is_null (weak_wrapper), empty ());
		var root = shared.operation (SharedAction.DOWNGRADE, read (parameter (0), 0), state, true);
		write (weak_wrapper, 0, root, true);
		write (weak_wrapper, 1, parameter (0), true);
		if (adapter.policy.declared_api != null) {
			write (weak_wrapper, 2, read (parameter (0), 1), true);
		}
		finish (weak_wrapper);
		start (CAbiClassRole.WEAK_CLONE, pointer, new CApi.TypeRef[] { pointer });
		refuse (is_null (parameter (0)), empty ());
		require_weak_thread (parameter (0), empty ());
		weak_wrapper = allocator.allocate (status (1), weak_control, "foreign.weak.clone", state, false, null, false, null, "", "object", true);
		refuse (is_null (weak_wrapper), empty ());
		root = shared.operation (SharedAction.WEAK_CLONE, read (parameter (0), 0, true), state, true);
		write (weak_wrapper, 0, root, true);
		write (weak_wrapper, 1, read (parameter (0), 1, true), true);
		if (adapter.policy.declared_api != null) {
			write (weak_wrapper, 2, load (artifact, builder, wide, address (artifact, builder, weak_control, parameter (0), 2)), true);
		}
		finish (weak_wrapper);
		start (CAbiClassRole.WEAK_UPGRADE, pointer, new CApi.TypeRef[] { pointer });
		refuse (is_null (parameter (0)), empty ());
		require_weak_thread (parameter (0), empty ());
		root = shared.operation (SharedAction.UPGRADE, read (parameter (0), 0, true), state, true);
		refuse (is_null (root), empty ());
		if (adapter.policy.declared_api != null) {
			change_duties (read (parameter (0), 1, true), true);
		}
		finish (read (parameter (0), 1, true));
		start (CAbiClassRole.WEAK_RELEASE, CApi.void_type_in_context (artifact.context), new CApi.TypeRef[] { pointer });
		refuse (is_null (parameter (0)), (CApi.ValueRef) null);
		require_weak_thread (parameter (0), (CApi.ValueRef) null);
		root = read (parameter (0), 0, true);
		shared.release_payload (root, owner, true, state);
		allocator.deallocate (parameter (0), "foreign.weak.free", state);
		finish ((CApi.ValueRef) null);
	}

	internal void lower(NativeAbiProgram native) throws LlvmError {
		native_program = native;
		if (adapter.policy.declared_api != null) {
			emit_declared ();
			return;
		}
		emit_factory ();
		emit_counts ();
		emit_properties ();
		emit_personality ();
		emit_weak ();
	}

}
}
