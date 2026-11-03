// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
using Astra.Source;
using Astra.NativeAbi;
using Astra.CAbi;
using Astra.Semantic;

namespace Astra.Backend.LLVM {
internal class LlvmForeignSignalBinding : Object {
	private LlvmSumSequence sequence;
	internal LlvmForeignSignalBinding (CApi.ValueRef function) {
		sequence = new LlvmSumSequence (function, true);
	}

	internal void verify() throws LlvmError {
		sequence.verify ();
	}

}
internal class LlvmForeignSignals : Object {
	internal static void lower(LlvmModuleArtifact artifact, LlvmTypeMapper types, NativeForeignSignalPlan plan, LlvmFunctionBinding native, LlvmStructRegistry structs, NativeAbiProgram program, Astra.Ssa.SsaClass owner) throws LlvmError {
		var builder = CApi.create_builder_in_context (artifact.context);
		var block = CApi.append_basic_block_in_context (artifact.context, native.value, "signal.emit.entry");
		CApi.position_builder_at_end (builder, block);
		CApi.ValueRef call = {};
		LlvmClassCallBinding? forwarded = null;
		if (plan.binding.root.active (ForeignClassPolicy.GOBJECT)) {
			uint count = CApi.count_params (native.value);
			var parameters = new CApi.TypeRef[count];
			var arguments = new CApi.ValueRef[count];
			uint[] bools = {};
			for (uint p = 0; p < count; p++) {
				arguments[p] = CApi.get_param (native.value, p);
				parameters[p] = CApi.type_of (arguments[p]);
				if ((void*) parameters[p] == (void*) CApi.int1_type_in_context (artifact.context)) {
					bools += p + 1;
				}
			}
			var cache_place = LlvmForeignClasses.cache_address (artifact, structs, program, builder, arguments[0], owner);
			var cache = CApi.build_load (builder, types.scalar (NativeScalarType.PTR), cache_place, "signal.receiver.cache");
			artifact.class_values.add (new LlvmClassValueBinding (cache, CApi.Opcode.LOAD, types.scalar (NativeScalarType.PTR), new CApi.ValueRef[] { cache_place }, "signal exact native-to-foreign cached receiver"));
			arguments[0] = cache;
			var bridge = LlvmForeignImports.external (artifact, plan.binding.symbol (), CApi.void_type_in_context (artifact.context), parameters);
			artifact.callback_c_bool.add (new LlvmCallbackCBoolBinding.physical (artifact, bridge.value, bools, false));
			call = CApi.build_call (builder, bridge.type, bridge.value, arguments, arguments.length, "");
			CApi.set_instruction_call_conv (call, CApi.CallConv.C);
			artifact.callback_c_bool.add (new LlvmCallbackCBoolBinding.physical (artifact, call, bools, true));
			bridge.record_call (call, arguments);
			forwarded = new LlvmClassCallBinding (call, bridge.value, bridge.type, arguments, CApi.CallConv.C, "native signal forwards cached receiver and exact physical argument order");
			artifact.class_calls.add (forwarded);
		}
		CApi.build_ret_void (builder);
		CApi.dispose_builder (builder);
		artifact.foreign_signals.add (new LlvmForeignSignalBinding (native.value));
		artifact.class_functions.add (new LlvmClassFunctionBinding (native.value, native.type));
	}

}
// Mechanical status/out -> native checked-call conversion. The provider
// owns the opaque object; no native layout or second reference count exists.
internal class LlvmForeignImports : Object {
	internal static LlvmCFunctionBinding external(LlvmModuleArtifact artifact, string name, CApi.TypeRef result, CApi.TypeRef[] parameters) throws LlvmError {
		var signature = CApi.function_type (result, parameters, parameters.length, 0);
		var existing = CApi.named_function (artifact.module, name);
		if ((void*) existing != null) {
			if ((void*) CApi.global_value_type(existing) != (void*) signature || CApi.function_call_conv(existing) != CApi.CallConv.C || (void*) CApi.first_block(existing) != null) {
				throw new LlvmError.LOWERING("CImport external symbol collision: " + name);
			}
			var binding = new LlvmCFunctionBinding(signature, existing, name);
			artifact.c_imports.add(binding);
			return binding;
		}
		var function = CApi.add_function (artifact.module, name, signature);
		CApi.set_function_call_conv (function, CApi.CallConv.C);
		CApi.set_linkage (function, CApi.Linkage.EXTERNAL);
		var binding = new LlvmCFunctionBinding (signature, function, name);
		artifact.c_imports.add (binding);
		return binding;
	}

	private static CApi.ValueRef call(CApi.BuilderRef builder, LlvmCFunctionBinding binding, CApi.ValueRef[] arguments, string name) {
		var result = CApi.build_call (builder, binding.type, binding.value, arguments, arguments.length, name);
		CApi.set_instruction_call_conv (result, CApi.CallConv.C);
		binding.record_call (result, arguments);
		return result;
	}

	internal static void trap(LlvmModuleArtifact artifact, CApi.BuilderRef builder) {
		CApi.TypeRef[] parameters = {};
		CApi.ValueRef[] arguments = {};
		var signature = CApi.function_type (CApi.void_type_in_context (artifact.context), parameters, 0, 0);
		var function = CApi.named_function (artifact.module, "llvm.trap");
		if ((void*) function == null) {
			function = CApi.add_function (artifact.module, "llvm.trap", signature);
		}
		CApi.build_call (builder, signature, function, arguments, 0, "");
		CApi.build_unreachable (builder);
	}

	private static CApi.TypeRef error_type(LlvmModuleArtifact artifact) {
		CApi.TypeRef[] fields = {
			CApi.int32_type_in_context (artifact.context), CApi.int32_type_in_context (artifact.context)
		};
		return CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
	}

	internal static LlvmSumSequence cleanup(LlvmModuleArtifact artifact, LlvmTypeMapper types, ForeignImportContract root, CApi.ValueRef function) throws LlvmError {
		var pointer = types.scalar (NativeScalarType.PTR);
		var i32 = types.scalar (NativeScalarType.I32);
		var zero = CApi.const_int (i32, 0, 0);
		CApi.set_linkage (function, CApi.Linkage.INTERNAL);
		var builder = CApi.create_builder_in_context (artifact.context);
		var entry = CApi.append_basic_block_in_context (artifact.context, function, "import.cleanup.entry");
		CApi.position_builder_at_end (builder, entry);
		if (root.api.active_personalities == 0) {
			trap (artifact, builder);
			CApi.dispose_builder (builder);
			return new LlvmSumSequence (function, true);
		}
		var result = CApi.append_basic_block_in_context (artifact.context, function, "import.cleanup.done");
		var live = CApi.append_basic_block_in_context (artifact.context, function, "import.cleanup.live");
		var owner = CApi.get_param (function, 0);
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, owner, CApi.const_null (pointer), "import.empty"), result, live);
		CApi.position_builder_at_end (builder, live);
		if (root.api.lifetime == ForeignLifetime.SHARED) {
			var provider = external (artifact, root.api.prefix + "_release", i32, new CApi.TypeRef[] { pointer });
			call (builder, provider, new CApi.ValueRef[] { owner }, "import.release");
			CApi.build_br (builder, result);
		} else {
			var slot = CApi.build_alloca (builder, pointer, "import.owner.slot");
			CApi.build_store (builder, owner, slot);
			var layout = error_type (artifact);
			var error = CApi.build_alloca (builder, layout, "import.cleanup.error");
			CApi.build_store (builder, CApi.const_null (layout), error);
			var provider = external (artifact, root.api.prefix + "_destroy", i32, new CApi.TypeRef[] { pointer, pointer });
			var status = call (builder, provider, new CApi.ValueRef[] { slot, error }, "import.destroy.status");
			var refused = CApi.build_icmp (builder, CApi.IntPredicate.NE, status, zero, "import.cleanup.status.invalid");
			refused = CApi.build_or (builder, refused, CApi.build_icmp (builder, CApi.IntPredicate.NE, CApi.build_load (builder, pointer, slot, "import.cleanup.remaining.owner"), CApi.const_null (pointer), "import.cleanup.owner.not.consumed"), "import.cleanup.owner.invalid");
			for (uint field = 0; field < 2; field++) {
				var value = CApi.build_load (builder, i32, CApi.build_struct_gep (builder, layout, error, field, "import.cleanup.error.field"), "import.cleanup.error.value");
				refused = CApi.build_or (builder, refused, CApi.build_icmp (builder, CApi.IntPredicate.NE, value, zero, "import.cleanup.error.not.clear"), "import.cleanup.invalid");
			}
			var failed = CApi.append_basic_block_in_context (artifact.context, function, "import.cleanup.refused");
			CApi.build_cond_br (builder, refused, failed, result);
			CApi.position_builder_at_end (builder, failed);
			trap (artifact, builder);
		}
		CApi.position_builder_at_end (builder, result);
		CApi.build_ret_void (builder);
		CApi.dispose_builder (builder);
		return new LlvmSumSequence (function, true);
	}

	internal static void lower(LlvmModuleArtifact artifact, LlvmTypeMapper types, LlvmTextLowering text, SourceSpan span, CAbiForeignImport physical, LlvmFunctionBinding native, LlvmFunctionBinding factory, LlvmCFunctionBinding? cleanup, LlvmCFunctionBinding?[] parameter_cleanups) throws LlvmError {
		if (!physical.valid () || native.signature.exception_plan == null) {
			throw new LlvmError.LOWERING ("CImport lost checked physical/native authority");
		}
		var member = physical.binding.member;
		var pointer = types.scalar (NativeScalarType.PTR);
		var i32 = types.scalar (NativeScalarType.I32);
		var zero = CApi.const_int (i32, 0, 0);
		var empty = CApi.const_null (pointer);
		bool owned_object = member.result.value_type.object_handle ();
		var builder = CApi.create_builder_in_context (artifact.context);
		var entry = CApi.append_basic_block_in_context (artifact.context, native.value, "import.entry");
		CApi.position_builder_at_end (builder, entry);
		if (physical.binding.root.api.active_personalities == 0) {
			trap (artifact, builder);
			CApi.dispose_builder (builder);
			artifact.foreign_imports.add (new LlvmSumSequence (native.value, true));
			artifact.class_functions.add (new LlvmClassFunctionBinding (native.value, native.type));
			return;
		}
		var c_types = new LlvmCTypeMapper (artifact.context);
		var parameter_types = new CApi.TypeRef[physical.parameters.length];
		var arguments = new CApi.ValueRef[physical.parameters.length];
		var declarations = new GenericArray<CAbiParameter> ();
		uint offset = native.signature.has_exception_success_slot ? 1 : 0;
		uint prefix = member.kind == ForeignMemberKind.CONSTRUCTOR ? 0 : 1;
		for (int p = 0; p < physical.parameters.length; p++) {
			parameter_types[p] = c_types.scalar (physical.parameters[p]);
			declarations.add (new CAbiParameter (span, span, "argument", p, physical.parameters[p]));
		}
		if (prefix != 0) {
			arguments[0] = CApi.get_param(native.value, offset);
		}
		var native_values = new CApi.ValueRef[member.parameter_count];
		var native_lengths = new CApi.ValueRef[member.parameter_count];
		uint component = offset + prefix;
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter(p);
			uint position = CAbiClassAdapter.declared_argument(member, p);
			if (channel.value_type.kind == ForeignValueKind.RECORD) {
				var storage = LlvmForeignRecordLayoutBinding.storage_type (artifact, types, channel.value_type);
				var snapshot = CApi.build_alloca (builder, storage, "import.record.argument");
				CApi.build_store (builder, CApi.const_null (storage), snapshot);
				for (uint f = 0; f < channel.value_type.field_count; f++) {
					CApi.build_store (builder, CApi.get_param (native.value, component++), CApi.build_struct_gep (builder, storage, snapshot, f, "import.record.input.field"));
				}
				arguments[position] = snapshot;
				continue;
			}
			native_values[p] = CApi.get_param(native.value, component++);
			if (CAbiClassAdapter.byte_sequence(channel.value_type.kind)) {
				native_lengths[p] = CApi.get_param(native.value, component++);
			} else {
				arguments[position] = native_values[p];
			}
		}
		var reference_slots = new CApi.ValueRef[member.parameter_count];
		var buffers = new LlvmImportBuffers (artifact, types, builder, native, factory, text, member, native_values, native_lengths, reference_slots);
		buffers.prepare_owners (arguments, parameter_cleanups);
		// Validate every mandatory place before touching caller storage.
		if (prefix != 0) {
			var valid = CApi.append_basic_block_in_context (artifact.context, native.value, "import.self.valid");
			var invalid = CApi.append_basic_block_in_context (artifact.context, native.value, "import.self.missing");
			CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, arguments[0], empty, "import.self.null"), invalid, valid);
			CApi.position_builder_at_end (builder, invalid);
			buffers.cleanup ();
			emit_error (artifact, builder, native, factory, zero, CApi.const_int (i32, 0x80004003, 0));
			CApi.position_builder_at_end (builder, valid);
		}
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (!channel.by_reference && !((channel.value_type.object_handle () || channel.value_type.kind == ForeignValueKind.CALLBACK) && !channel.nullable)) {
				continue;
			}
			var valid = CApi.append_basic_block_in_context (artifact.context, native.value, "import.reference.valid");
			var invalid = CApi.append_basic_block_in_context (artifact.context, native.value, "import.reference.missing");
			CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, native_values[p], empty, "import.reference.null"), invalid, valid);
			CApi.position_builder_at_end (builder, invalid);
			buffers.cleanup ();
			emit_error (artifact, builder, native, factory, zero, CApi.const_int (i32, 0x80004003, 0));
			CApi.position_builder_at_end (builder, valid);
		}
		// Snapshot all inputs before initializing any aliased output place.
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (channel.value_type.kind != ForeignValueKind.CALLBACK) {
				continue;
			}
			var callbacks = new LlvmCallbackRuntime (artifact, types);
			uint position = CAbiClassAdapter.declared_argument (member, p);
			arguments[position] = callbacks.to_c (builder, channel.value_type, native_values[p], channel.nullable);
			arguments[position + 1] = native_values[p];
		}
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (!channel.by_reference) {
				continue;
			}
			var element = types.scalar (NativeForeignApi.scalar (channel.value_type.kind));
			var slot = CApi.build_alloca (builder, element, "import.reference.scratch");
			var initial = channel.direction == ForeignDirection.OUT ? CApi.const_null (element) : CApi.build_load (builder, element, native_values[p], "import.reference.input");
			CApi.build_store (builder, initial, slot);
			reference_slots[p] = slot;
			arguments[CAbiClassAdapter.declared_argument(member, p)] = slot;
		}
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (channel.by_reference && channel.direction == ForeignDirection.OUT) {
				CApi.build_store (builder, CApi.const_null (types.scalar (NativeForeignApi.scalar (channel.value_type.kind))), native_values[p]);
			}
		}

		buffers.bind_references (reference_slots);
		buffers.prepare(arguments);
		CApi.ValueRef success = (CApi.ValueRef) (void*) null;
		CApi.TypeRef success_type = (CApi.TypeRef) (void*) null;
		if (member.result.value_type.kind != ForeignValueKind.VOID) {
			success_type = member.result.value_type.kind == ForeignValueKind.RECORD ? LlvmForeignRecordLayoutBinding.storage_type (artifact, types, member.result.value_type) : types.success_result_type (native.signature);
			success = CApi.build_alloca (builder, success_type, "import.private.success");
			CApi.build_store (builder, CApi.const_null (success_type), success);
			arguments[CAbiClassAdapter.declared_result(member)] = success;
		}
		buffers.prepare_result (arguments, success);
		var error_layout = error_type (artifact);
		var error = CApi.build_alloca (builder, error_layout, "import.private.error");
		CApi.build_store (builder, CApi.const_null (error_layout), error);
		arguments[arguments.length - 1] = error;
		var signature = new CAbiSignature (CAbiProfile.C_BOOL_V7, declarations, new CAbiResult (CAbiScalarType.I32), null, Astra.Foreign.CBoolAbi.C99);
		artifact.requires_c_bool |= signature.has_bool;
		artifact.requires_c_wide |= signature.has_wide;
		foreach (var parameter in signature.parameters) {
			artifact.requires_c_floating |= parameter.scalar_type == CAbiScalarType.F32 || parameter.scalar_type == CAbiScalarType.F64;
		}
		var provider = external (artifact, physical.symbol (), i32, parameter_types);
		c_types.attributes (signature, provider.value);
		provider.record_record_attributes (signature, c_types, provider.value);
		var status = call (builder, provider, arguments, "import.status");
		c_types.attributes (signature, status, true);
		provider.record_record_attributes (signature, c_types, status, true);
		var domain = CApi.build_load (builder, i32, CApi.build_struct_gep (builder, error_layout, error, 0, "import.domain.slot"), "import.domain");
		var code = CApi.build_load (builder, i32, CApi.build_struct_gep (builder, error_layout, error, 1, "import.code.slot"), "import.code");
		var cleared = CApi.build_and (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, domain, zero, "import.domain.clear"), CApi.build_icmp (builder, CApi.IntPredicate.EQ, code, zero, "import.code.clear"), "import.error.clear");
		var admitted_success = CApi.build_icmp (builder, CApi.IntPredicate.EQ, status, zero, "import.declared.success");
		if (member.null_status != 0) {
			var absent = CApi.build_icmp (builder, CApi.IntPredicate.EQ, CApi.build_load (builder, pointer, success, "import.null.status.owner"), empty, "import.null.status.absent");
			var declared = CApi.build_icmp (builder, CApi.IntPredicate.EQ, status, CApi.const_int (i32, (uint32) member.null_status, 0), "import.null.status.declared");
			admitted_success = CApi.build_or (builder, admitted_success, CApi.build_and (builder, absent, declared, "import.null.status.valid"), "import.admitted.success");
		}
		var success_status = CApi.build_and (builder, admitted_success, cleared, "import.valid.success");
		var failed = CApi.append_basic_block_in_context (artifact.context, native.value, "import.failed");
		var succeeded = CApi.append_basic_block_in_context (artifact.context, native.value, "import.succeeded");
		CApi.build_cond_br (builder, success_status, succeeded, failed);
		CApi.position_builder_at_end (builder, failed);
		buffers.cleanup();
		buffers.retire_result ();
		if (owned_object) {
			if (cleanup == null) {
				throw new LlvmError.LOWERING ("CImport owned result lost exact root retirement");
			}
			var provisional = CApi.build_load (builder, pointer, success, "import.failed.provisional");
			call (builder, cleanup, new CApi.ValueRef[] { provisional }, "");
		}
		var declared_status = CApi.const_int (CApi.int1_type_in_context (artifact.context), 0, 0);
		for (uint c = 0; c < member.error_map.case_count; c++) {
			declared_status = CApi.build_or (builder, declared_status, CApi.build_icmp (builder, CApi.IntPredicate.EQ, status, CApi.const_int (i32, (uint32) member.error_map.at (c).status, 0), "import.named.error"), "import.declared.error");
		}
		var declared_domain = CApi.build_and (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, domain, CApi.const_int (i32, member.error_map.domain, 0), "import.named.domain"), declared_status, "import.named.failure");
		var admitted_domain = CApi.build_or (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, domain, zero, "import.infrastructure.domain"), declared_domain, "import.admitted.domain");
		var consistent = CApi.build_and (builder, admitted_domain, CApi.build_icmp (builder, CApi.IntPredicate.EQ, code, status, "import.error.matches.status"), "import.consistent.error");
		var admitted = CApi.build_and (builder, consistent, CApi.build_icmp (builder, CApi.IntPredicate.SLT, status, zero, "import.failure.status"), "import.admitted.failure");
		emit_error (artifact, builder, native, factory, CApi.build_select (builder, admitted, domain, zero, "import.checked.domain"), CApi.build_select (builder, admitted, status, CApi.const_int (i32, 0x8000ffff, 0), "import.checked.status"));
		CApi.position_builder_at_end (builder, succeeded);
		if (owned_object && !member.result.nullable) {
			var checked = CApi.append_basic_block_in_context (artifact.context, native.value, "import.owner.valid");
			var missing = CApi.append_basic_block_in_context (artifact.context, native.value, "import.owner.missing");
			var value = CApi.build_load (builder, pointer, success, "import.owner");
			CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, value, empty, "import.null.owner"), missing, checked);
			CApi.position_builder_at_end (builder, missing);
			buffers.cleanup();
			emit_error (artifact, builder, native, factory, zero, CApi.const_int (i32, 0x8000ffff, 0));
			CApi.position_builder_at_end (builder, checked);
		}
		if (owned_object) {
			buffers.protect_owner(cleanup, success);
		}
		buffers.cleanup_owners ();
		buffers.validate(success);
		buffers.convert_result ();
		buffers.publish();
		buffers.cleanup();
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			if (!channel.by_reference || channel.direction == ForeignDirection.IN) {
				continue;
			}
			var value = CApi.build_load (builder, types.scalar (NativeForeignApi.scalar (channel.value_type.kind)), reference_slots[p], "import.reference.commit");
			CApi.build_store (builder, value, native_values[p]);
		}
		if (member.result.value_type.kind == ForeignValueKind.RECORD) {
			var declaration = member.result.value_type;
			var carrier = types.success_result_type (native.signature);
			var value = CApi.const_null (carrier);
			for (uint f = 0; f < declaration.field_count; f++) {
				var leaf = CApi.build_load (builder, types.scalar (NativeForeignApi.scalar (declaration.field (f).kind)), CApi.build_struct_gep (builder, success_type, success, f, "import.record.result.field"), "import.record.result.leaf");
				value = declaration.field_count == 1 ? leaf : CApi.build_insert_value (builder, value, leaf, f, "import.record.native.result");
			}
			CApi.build_store (builder, value, CApi.get_param (native.value, 0));
		} else if (member.result.value_type.kind != ForeignValueKind.VOID) {
			CApi.build_store (builder, CApi.build_load (builder, success_type, success, "import.success.value"), CApi.get_param (native.value, 0));
		}
		CApi.build_ret (builder, empty);
		CApi.dispose_builder (builder);
		artifact.foreign_imports.add (new LlvmSumSequence (native.value, true));
		artifact.class_functions.add (new LlvmClassFunctionBinding (native.value, native.type));
	}

	internal static void emit_error(LlvmModuleArtifact artifact, CApi.BuilderRef builder, LlvmFunctionBinding native, LlvmFunctionBinding factory, CApi.ValueRef domain, CApi.ValueRef status) throws LlvmError {
		CApi.ValueRef[] arguments = {
			domain, status
		};
		var error = CApi.build_call (builder, factory.type, factory.value, arguments, arguments.length, "import.native.exception");
		CApi.set_instruction_call_conv (error, LlvmLowering.CALL_CONVENTION);
		artifact.class_calls.add (new LlvmClassCallBinding (error, factory.value, factory.type, arguments, LlvmLowering.CALL_CONVENTION, "exact native imported-error factory"));
		var invalid = CApi.append_basic_block_in_context (artifact.context, native.value, "import.exception.missing");
		var ready = CApi.append_basic_block_in_context (artifact.context, native.value, "import.exception.ready");
		CApi.build_cond_br (builder, CApi.build_icmp (builder, CApi.IntPredicate.EQ, error, CApi.const_null (CApi.type_of (error)), "import.empty.exception"), invalid, ready);
		CApi.position_builder_at_end (builder, invalid);
		trap (artifact, builder);
		CApi.position_builder_at_end (builder, ready);
		CApi.build_ret (builder, error);
	}

}

// Construction-local bounded data staging. Only initialized prefixes publish.
internal class LlvmImportBuffers : Object {
	private LlvmModuleArtifact artifact;
	private LlvmTypeMapper types;
	private CApi.BuilderRef builder;
	private LlvmFunctionBinding native;
	private LlvmFunctionBinding factory;
	private LlvmTextLowering text;
	private ForeignMemberContract member;
	private CApi.ValueRef[] native_values;
	private CApi.ValueRef[] native_lengths;
	private CApi.ValueRef[] references;
	private LlvmCFunctionBinding? provisional_cleanup;
	private CApi.ValueRef provisional_slot;
	internal void protect_owner(LlvmCFunctionBinding cleanup, CApi.ValueRef slot) {
		provisional_cleanup = cleanup;
		provisional_slot = slot;
	}

	private CApi.ValueRef[] allocations = null;
	private CApi.ValueRef[] scratch;
	private CApi.ValueRef[] counts;
	private CApi.ValueRef[] produced;
	private CApi.ValueRef result_data;
	private CApi.ValueRef result_length;
	private CApi.ValueRef result_success;
	private bool owned_result;
	private CApi.ValueRef[] owned_slots;
	private LlvmCFunctionBinding?[] owned_cleanups;
	private CApi.TypeRef pointer;
	private CApi.TypeRef i32;
	private CApi.TypeRef wide;
	internal LlvmImportBuffers (LlvmModuleArtifact artifact, LlvmTypeMapper types, CApi.BuilderRef builder, LlvmFunctionBinding native, LlvmFunctionBinding factory, LlvmTextLowering text, ForeignMemberContract member, CApi.ValueRef[] values, CApi.ValueRef[] lengths, CApi.ValueRef[] references) throws LlvmError {
		this.artifact = artifact;
		this.types = types;
		this.builder = builder;
		this.native = native;
		this.factory = factory;
		this.text = text;
		this.member = member;
		native_values = values;
		native_lengths = lengths;
		this.references = references;
		scratch = new CApi.ValueRef[member.parameter_count];
		counts = new CApi.ValueRef[member.parameter_count];
		produced = new CApi.ValueRef[member.parameter_count];
		pointer = types.scalar (NativeScalarType.PTR);
		i32 = types.scalar (NativeScalarType.I32);
		wide = types.scalar (NativeScalarType.U64);
	}

	private CApi.ValueRef number(uint32 value) {
		return CApi.const_int (i32, value, 0);
	}

	private CApi.ValueRef compare(CApi.IntPredicate predicate, CApi.ValueRef left, CApi.ValueRef right, string name) {
		return CApi.build_icmp (builder, predicate, left, right, name);
	}

	private void refuse(CApi.ValueRef condition, uint32 status) throws LlvmError {
		var failed = CApi.append_basic_block_in_context (artifact.context, native.value, "import.data.refused");
		var valid = CApi.append_basic_block_in_context (artifact.context, native.value, "import.data.valid");
		CApi.build_cond_br (builder, condition, failed, valid);
		CApi.position_builder_at_end (builder, failed);
		cleanup ();
		retire_result ();
		if (provisional_cleanup != null) {
			invoke(provisional_cleanup, new CApi.ValueRef[] {CApi.build_load(builder, pointer, provisional_slot, "import.provisional.owner")}, "");
		}
		LlvmForeignImports.emit_error (artifact, builder, native, factory, number(0), number(status));
		CApi.position_builder_at_end (builder, valid);
	}

	private CApi.ValueRef invoke(LlvmCFunctionBinding function, CApi.ValueRef[] arguments, string name) {
		var result = CApi.build_call (builder, function.type, function.value, arguments, arguments.length, name);
		CApi.set_instruction_call_conv (result, CApi.CallConv.C);
		function.record_call (result, arguments);
		return result;
	}

	internal void cleanup() throws LlvmError {
		cleanup_owners ();
		if (allocations.length == 0) {
			return;
		}
		var release = LlvmForeignImports.external (artifact, "free", CApi.void_type_in_context(artifact.context), new CApi.TypeRef[] {pointer});
		for (int p = allocations.length - 1; p >= 0; p--) {
			invoke (release, new CApi.ValueRef[] {allocations[p]}, "");
		}
	}

	internal void prepare_owners(CApi.ValueRef[] arguments, LlvmCFunctionBinding?[] cleanups) throws LlvmError {
		if (cleanups.length != member.parameter_count) {
			throw new LlvmError.LOWERING ("CImport owned input lost exact cleanup inventory");
		}
		owned_slots = new CApi.ValueRef[member.parameter_count];
		owned_cleanups = cleanups;
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter (p);
			bool consumes = channel.value_type.object_handle () && channel.transfer == ForeignTransfer.OWN;
			if (consumes != (cleanups[p] != null)) {
				throw new LlvmError.LOWERING ("CImport owned input lost its exact root cleanup");
			}
			if (!consumes) {
				continue;
			}
			var slot = CApi.build_alloca (builder, pointer, "import.input.owner.slot");
			CApi.build_store (builder, native_values[p], slot);
			owned_slots[p] = slot;
			arguments[CAbiClassAdapter.declared_argument (member, p)] = slot;
		}
	}

	internal void bind_references(CApi.ValueRef[] values) {
		references = values;
	}

	internal void cleanup_owners() throws LlvmError {
		for (int p = owned_slots.length - 1; p >= 0; p--) {
			if (owned_cleanups[p] == null) {
				continue;
			}
			var value = CApi.build_load (builder, pointer, owned_slots[p], "import.input.owner.remaining");
			CApi.build_store (builder, CApi.const_null (pointer), owned_slots[p]);
			invoke (owned_cleanups[p], new CApi.ValueRef[] { value }, "");
		}
	}

	private void copy(CApi.ValueRef destination, CApi.ValueRef source, CApi.ValueRef length) {
		uint id = CApi.lookup_intrinsic_id("llvm.memcpy", 11);
		CApi.TypeRef[] overloads = {
			pointer, pointer, wide
		};
		var function = CApi.get_intrinsic_declaration(artifact.module, id, overloads, overloads.length);
		var signature = CApi.intrinsic_get_type(artifact.context, id, overloads, overloads.length);
		CApi.ValueRef[] arguments = {
			destination, source, CApi.build_zext(builder, length, wide, "import.copy.extent"), CApi.const_null(CApi.int1_type_in_context(artifact.context))
		};
		var call = CApi.build_call(builder, signature, function, arguments, arguments.length, "");
		CApi.set_instruction_call_conv(call, CApi.CallConv.C);
		artifact.class_calls.add(new LlvmClassCallBinding(call, function, signature, arguments, CApi.CallConv.C, "import exact initialized byte prefix"));
	}

	internal void prepare(CApi.ValueRef[] arguments) throws LlvmError {
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter(p);
			if (!CAbiClassAdapter.byte_sequence(channel.value_type.kind)) {
				continue;
			}
			var length = native_lengths[p];
			var count = channel.intrinsic_length || channel.encoding == ForeignTextEncoding.UTF8_NUL ? length : native_values[channel.direction == ForeignDirection.IN ? channel.length_index : channel.capacity_index];
			counts[p] = count;
			refuse(CApi.build_or(builder, compare(CApi.IntPredicate.SLT, count, number(0), "import.count.negative"), compare(CApi.IntPredicate.NE, count, length, "import.count.native.mismatch"), "import.count.invalid"), 0x80070057U);
			var nonempty = compare(CApi.IntPredicate.NE, count, number(0), "import.data.required");
			var missing = compare(CApi.IntPredicate.EQ, native_values[p], CApi.const_null(pointer), "import.data.missing");
			refuse(CApi.build_and(builder, nonempty, missing, "import.data.pointer.invalid"), 0x80004003U);
			if (channel.encoding == ForeignTextEncoding.UTF8_NUL) {
				refuse(compare(CApi.IntPredicate.SGE, text.find_nul(builder, native_values[p], count), number(0), "import.text.embedded.nul"), 0x80070057U);
			}
			var extent = CApi.build_zext(builder, count, wide, "import.data.extent");
			if (channel.value_type.kind == ForeignValueKind.TEXT) {
				extent = CApi.build_add(builder, extent, CApi.const_int(wide, 1, 0), "import.text.sentinel.extent");
			}
			extent = CApi.build_select(builder, compare(CApi.IntPredicate.EQ, count, number(0), "import.data.empty"), CApi.const_int(wide, 1, 0), extent, "import.nonempty.allocation");
			artifact.requires_hosted_buffers = true;
			var allocate = LlvmForeignImports.external(artifact, "calloc", pointer, new CApi.TypeRef[] {wide, wide});
			var data = invoke(allocate, new CApi.ValueRef[] {CApi.const_int(wide, 1, 0), extent}, "import.data.scratch");
			refuse(compare(CApi.IntPredicate.EQ, data, CApi.const_null(pointer), "import.data.oom"), 0x8007000eU);
			allocations += data;
			scratch[p] = data;
			if (channel.direction != ForeignDirection.OUT) {
				copy(data, native_values[p], count);
			}
			uint position = CAbiClassAdapter.declared_argument(member, p);
			arguments[position] = data;
			if (channel.intrinsic_length) {
				arguments[position + 1] = count;
			}
		}
	}

	internal void prepare_result(CApi.ValueRef[] arguments, CApi.ValueRef success) {
		if (!CAbiClassAdapter.byte_sequence (member.result.value_type.kind)) {
			return;
		}
		owned_result = true;
		result_success = success;
		result_data = CApi.build_alloca (builder, pointer, "import.result.provider.data");
		CApi.build_store (builder, CApi.const_null (pointer), result_data);
		result_length = CApi.build_alloca (builder, i32, "import.result.provider.length");
		CApi.build_store (builder, number (0), result_length);
		uint position = CAbiClassAdapter.declared_result (member);
		arguments[position] = result_data;
		arguments[position + 1] = result_length;
	}

	internal void retire_result() throws LlvmError {
		if (!owned_result) {
			return;
		}
		CApi.TypeRef[] fields = {
			i32, i32
		};
		var layout = CApi.struct_type_in_context (artifact.context, fields, fields.length, 0);
		var error = CApi.build_alloca (builder, layout, "import.result.release.error");
		CApi.build_store (builder, CApi.const_null (layout), error);
		var release = LlvmForeignImports.external (artifact, member.result.release_symbol, i32, new CApi.TypeRef[] { pointer, pointer, pointer });
		var status = invoke (release, new CApi.ValueRef[] { result_data, result_length, error }, "import.result.release.status");
		var valid = compare (CApi.IntPredicate.EQ, status, number (0), "import.result.release.succeeded");
		valid = CApi.build_and (builder, valid, compare (CApi.IntPredicate.EQ, CApi.build_load (builder, pointer, result_data, "import.result.released.data"), CApi.const_null (pointer), "import.result.owner.consumed"), "import.result.release.owner.valid");
		valid = CApi.build_and (builder, valid, compare (CApi.IntPredicate.EQ, CApi.build_load (builder, i32, result_length, "import.result.released.length"), number (0), "import.result.length.consumed"), "import.result.release.length.valid");
		for (uint field = 0; field < 2; field++) {
			valid = CApi.build_and (builder, valid, compare (CApi.IntPredicate.EQ, CApi.build_load (builder, i32, CApi.build_struct_gep (builder, layout, error, field, "import.result.release.error.field"), "import.result.release.error.value"), number (0), "import.result.release.error.clear"), "import.result.release.valid");
		}
		var refused = CApi.append_basic_block_in_context (artifact.context, native.value, "import.result.release.refused");
		var retired = CApi.append_basic_block_in_context (artifact.context, native.value, "import.result.released");
		CApi.build_cond_br (builder, valid, retired, refused);
		CApi.position_builder_at_end (builder, refused);
		LlvmForeignImports.trap (artifact, builder);
		CApi.position_builder_at_end (builder, retired);
	}

	internal void convert_result() throws LlvmError {
		if (!owned_result) {
			return;
		}
		var data = CApi.build_load (builder, pointer, result_data, "import.result.data");
		var length = CApi.build_load (builder, i32, result_length, "import.result.length");
		refuse (compare (CApi.IntPredicate.SLT, length, number (0), "import.result.length.negative"), 0x8000ffffU);
		var required = compare (CApi.IntPredicate.NE, length, number (0), "import.result.nonempty");
		if (member.result.encoding == ForeignTextEncoding.UTF8_NUL) {
			required = CApi.const_int (CApi.int1_type_in_context (artifact.context), 1, 0);
		}
		refuse (CApi.build_and (builder, required, compare (CApi.IntPredicate.EQ, data, CApi.const_null (pointer), "import.result.missing"), "import.result.invalid.pointer"), 0x8000ffffU);
		if (member.result.value_type.kind == ForeignValueKind.TEXT) {
			refuse (compare (CApi.IntPredicate.EQ, text.validate_counted_utf8 (builder, data, length), CApi.const_null (CApi.int1_type_in_context (artifact.context)), "import.result.invalid.utf8"), 0x80070057U);
			if (member.result.encoding == ForeignTextEncoding.UTF8_NUL) {
				refuse (compare (CApi.IntPredicate.SGE, text.find_nul (builder, data, length), number (0), "import.result.embedded.nul"), 0x80070057U);
				CApi.ValueRef[] index = {
					length
				};
				var byte = types.scalar (NativeScalarType.U8);
				var sentinel = CApi.build_gep (builder, byte, data, index, index.length, "import.result.sentinel");
				refuse (compare (CApi.IntPredicate.NE, CApi.build_load (builder, byte, sentinel, "import.result.sentinel.value"), CApi.const_null (byte), "import.result.sentinel.missing"), 0x80070057U);
			}
		}
		artifact.requires_hosted_buffers = true;
		var allocate = LlvmForeignImports.external (artifact, "calloc", pointer, new CApi.TypeRef[] { wide, wide });
		var extent = CApi.build_select (builder, compare (CApi.IntPredicate.EQ, length, number (0), "import.result.empty"), CApi.const_int (wide, 1, 0), CApi.build_zext (builder, length, wide, "import.result.extent"), "import.result.allocation.extent");
		var snapshot = invoke (allocate, new CApi.ValueRef[] { extent, CApi.const_int (wide, 1, 0) }, "import.result.native.snapshot");
		refuse (compare (CApi.IntPredicate.EQ, snapshot, CApi.const_null (pointer), "import.result.snapshot.oom"), 0x8007000eU);
		copy (snapshot, data, length);
		retire_result ();
		var carrier = types.buffer_carrier ();
		var value = CApi.build_insert_value (builder, CApi.const_null (carrier), snapshot, 0, "import.result.native.data");
		value = CApi.build_insert_value (builder, value, length, 1, "import.result.native.buffer");
		CApi.build_store (builder, value, result_success);
	}

	internal void validate(CApi.ValueRef success) throws LlvmError {
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter(p);
			if (channel.value_type.kind != ForeignValueKind.BYTES || channel.direction == ForeignDirection.IN) {
				continue;
			}
			var count = CApi.build_load(builder, i32, channel.produced_by_result ? success : references[channel.produced_index], "import.data.produced");
			produced[p] = count;
			refuse(CApi.build_or(builder, compare(CApi.IntPredicate.SLT, count, number(0), "import.produced.negative"), compare(CApi.IntPredicate.SGT, count, counts[p], "import.produced.excess"), "import.produced.invalid"), 0x8000ffffU);
		}
	}

	internal void publish() {
		for (uint p = 0; p < member.parameter_count; p++) {
			var channel = member.parameter(p);
			if (channel.value_type.kind == ForeignValueKind.BYTES && channel.direction != ForeignDirection.IN) {
				copy(native_values[p], scratch[p], produced[p]);
			}
		}
	}

}

}
