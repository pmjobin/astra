// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Backend.LLVM {
// Separate from the closed no-OS profile and from COM qualification. This
// object-only target initially admits copied words/pointers and plain native
// intrusive Shared ownership. Unsupported Linux services cannot enter it.
public class LlvmWindowsInteropProfile : Object {
	private static void reject(string detail) throws LlvmError {
		throw new LlvmError.TARGET ("Windows interop object profile: unsupported %s", detail);
	}

	internal static bool declarations(SsaProgram program) {
		foreach (var owner in program.classes) {
			if (owner.foreign_export != null && owner.foreign_export.declared_api != null) {
				return true;
			}
		}
		foreach (var handle in program.handles) {
			if (handle.c_import != null) {
				return true;
			}
		}
		return false;
	}

	internal static void require_declared_value(SemanticType type) throws LlvmError {
		if (type.kind == TypeKind.VOID || type.kind == TypeKind.BOOL || type is RawPointerType || type is StringType) {
			return;
		}
		if (type is IntegerType && ((IntegerType) type).bit_width <= 64 || type is FloatingType) {
			return;
		}
		if (type is CallbackType && ((CallbackType) type).supported () && !type.is_parameterized ()) {
			return;
		}
		if (type is ClosureHandleType) {
			var closure = (ClosureHandleType) type;
			bool copied = !closure.threaded && !closure.actor && closure.throws_type == null && closure.result_contract == ResultOwnershipContract.UNMANAGED && (closure.result_type.kind == TypeKind.VOID || CallbackType.copied (closure.result_type));
			for (int p = 0; p < closure.parameter_types.length; p++) {
				copied &= CallbackType.copied (closure.parameter_types[p]) && closure.parameter_contract (p) == PointerParameterContract.UNMANAGED;
			}
			if (copied && closure.supported () && !closure.is_parameterized ()) {
				require_declared_value (closure.environment_type);
				return;
			}
		}

		if (type is ReceiverType) {
			require_declared_value (((ReceiverType) type).instance_type);
			return;
		}
		if (type is TypedPointerType) {
			require_declared_value (((TypedPointerType) type).pointee);
			return;
		}
		if (type is SliceType) {
			require_declared_value (((SliceType) type).element_type);
			return;
		}
		if (type is ArrayType) {
			require_declared_value (((ArrayType) type).element_type);
			return;
		}
		if (type is OwnerSlotsType) {
			require_declared_value (((OwnerSlotsType) type).element);
			return;
		}
		if (type.is_struct_storage () && !type.is_parameterized ()) {
			return;
		}
		if (type is ClassType) {
			var owner = (ClassType) type;
			if (!owner.is_interface && !owner.is_parameterized () && (owner.concurrency_policy_identity == 0 || owner.concurrency_policy_identity == 1)) {
				return;
			}
		}
		if (type is SharedHandleType) {
			require_declared_value (((SharedHandleType) type).payload_type);
			return;
		}
		if (type.get_type () == typeof (HandleType)) {
			return;
		}
		reject ("declarations-v1 type " + type.display_name ());
	}

	private static void validate_declarations(SsaProgram program, bool native_modules = false) throws LlvmError {
		if (program.enums.length != 0) {
			reject ("declarations-v1 enum storage");
		}
		foreach (var handle in program.handles) {
			require_declared_value (handle.semantic_type);
		}
		foreach (var structure in program.structs) {
			foreach (var field in structure.fields) {
				require_declared_value (field.semantic_type);
			}
		}
		foreach (var owner in program.classes) {
			require_declared_value (owner.semantic_type);
			if (owner.allocation_policy != null) {
				reject ("declarations-v1 allocation policy");
			}
			foreach (var field in owner.fields) {
				require_declared_value (field.semantic_type);
			}
			foreach (var property in owner.properties) {
				require_declared_value (property.semantic_type);
			}
		}
		foreach (var imported in program.c_functions) {
			require_metadata (imported.metadata);
			require_declared_value (imported.return_type);
			foreach (var parameter in imported.parameters) {
				require_declared_value (parameter.semantic_type);
			}
		}
		foreach (var function in program.functions) {
			if (function.module_import_symbol != null && !native_modules || function.async_body != null || function.enum_slots.length != 0) {
				reject ("declarations-v1 native module, async or enum storage");
			}
			require_declared_value (function.return_type);
			foreach (var parameter in function.parameters) {
				require_declared_value (parameter.semantic_type);
			}
			foreach (var storage in function.storage) {
				require_declared_value (storage.semantic_type);
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction.result != null) {
						require_declared_value (instruction.result.semantic_type);
					}
				}
			}
		}
	}

	private static bool value(SemanticType type) {
		if (type.kind == TypeKind.VOID || type.kind == TypeKind.BOOL || type is RawPointerType) {
			return true;
		}
		if (type is IntegerType) {
			return ((IntegerType) type).bit_width <= 32;
		}
		if (type is ReceiverType) {
			return value (((ReceiverType) type).instance_type);
		}
		if (CPlainRecordTypes.i32_pointer (type)) {
			return true;
		}
		if (type is SharedHandleType) {
			var handle = (SharedHandleType) type;
			return handle.is_weak && value (handle.payload_type);
		}
		if (type is HandleType) {
			return ((HandleType) type).foreign_policy_identity.has_prefix ("COMImport;windows-x64-v1;");
		}
		if (type is ClassType) {
			var owner = (ClassType) type;
			return owner.intrinsically_shared && owner.concurrency_policy_identity == 1 && !owner.is_interface && !(owner is ExactGenericClassType);
		}
		return false;
	}

	internal static void require_value(SemanticType type) throws LlvmError {
		if (!value (type)) {
			reject ("type " + type.display_name ());
		}
	}

	internal static void require_metadata(Astra.Foreign.CForeignMetadata metadata) throws LlvmError {
		if (!metadata.valid_com () || metadata.owned_result != null && !metadata.com_owner_result || metadata.device != null || metadata.callback != null || metadata.callback_abi != Astra.Foreign.CCallbackAbi.NONE || metadata.record_abi != Astra.Foreign.CRecordAbi.NONE || metadata.text_abi != Astra.Foreign.CTextAbi.NONE || metadata.buffer_abi != Astra.Foreign.CBufferAbi.NONE) {
			reject ("alternate C transport or provider protocol");
		}
	}

	public static void validate_source(SsaProgram program, bool native_modules = false) throws LlvmError {
		if (declarations (program) || native_modules) {
			validate_declarations (program, native_modules);
			return;
		}
		if (program.structs.length != 0 || program.enums.length != 0 || program.text_literals.length != 0) {
			reject ("aggregate, text or resource storage");
		}
		foreach (var handle in program.handles) {
			require_value (handle.semantic_type);
		}
		foreach (var owner in program.classes) {
			require_value (owner.semantic_type);
			if (owner.parent_class != null || owner.polymorphic || owner.exception_root || owner.allocation_policy != null) {
				reject ("Class inheritance, exception or allocation policy");
			}
			foreach (var field in owner.fields) {
				if (field.owned_cleanup != null || field.slots_cleanup != null) {
					reject ("owning Class field");
				}
				require_value (field.semantic_type);
			}
			foreach (var property in owner.properties) {
				if (property.is_lazy) {
					reject ("lazy property");
				}
				require_value (property.semantic_type);
			}
		}
		foreach (var imported in program.c_functions) {
			require_metadata (imported.metadata);
			require_value (imported.return_type);
			foreach (var parameter in imported.parameters) {
				require_value (parameter.semantic_type);
			}
		}
		foreach (var function in program.functions) {
			if (function.module_import_symbol != null || function.async_body != null || function.throws_type != null || function.buffer_storage.length != 0 || function.enum_slots.length != 0) {
				reject ("native module, async, exception, buffer or enum storage");
			}
			require_value (function.return_type);
			foreach (var parameter in function.parameters) {
				require_value (parameter.semantic_type);
			}
			foreach (var storage in function.storage) {
				require_value (storage.semantic_type);
			}
			foreach (var block in function.blocks) {
				foreach (var instruction in block.instructions) {
					if (instruction.result != null) {
						require_value (instruction.result.semantic_type);
					}
				}
			}
		}
	}

}

// An opt-in closed source domain, checked before any product is emitted.
// Startup and operating-system services are deliberately separate objects.
public class LlvmRuntimeProfile : Object {
	private string target_name;
	internal HashTable<SemanticType, bool> local_classes = new HashTable<SemanticType, bool> (direct_hash, direct_equal);
	public string target { get { return target_name; } }
	public bool cross_object { get; private set; }

	public LlvmRuntimeProfile (string target, bool cross_object = false) {
		this.target_name = target;
		this.cross_object = cross_object;
	}

	internal bool value_type(SemanticType type, bool storage = false) {
		if (type.kind == Semantic.TypeKind.VOID || type.kind == Semantic.TypeKind.BOOL) {
			return true;
		}
		if (type is IntegerType) {
			return !cross_object || ((IntegerType) type).bit_width <= 32;
		}
		if (cross_object) {
			return false;
		}
		if (type is FloatingType) {
			return true;
		}
		if (type is SliceType) {
			var element = ((SliceType) type).element_type;
			return element is IntegerType || element is FloatingType;
		}
		if (type is VectorType) {
			var vector = (VectorType) type;
			return VectorType.supports (vector.element_type, vector.lane_count);
		}
		if (type is TypedPointerType) {
			return value_type (((TypedPointerType) type).pointee, true);
		}
		if (type is StructType) {
			return true;
		}
		if (type is ClassType) {
			return target == LlvmTargetMachineArtifact.PC_BARE_METAL && local_classes.contains (type);
		}
		if (type is ReceiverType) {
			return ((ReceiverType) type).instance_type is StructType || value_type (((ReceiverType) type).instance_type);
		}
		if (storage && type is ArrayType) {
			return value_type (((ArrayType) type).element_type, true);
		}
		return false;
	}

	private static void reject(string detail) throws LlvmError {
		throw new LlvmError.INVALID_INPUT ("runtime none: unsupported source requirement: %s", detail);
	}

	public void validate_source(SsaProgram program) throws LlvmError {
		SsaFunction? trap_handler = null;
		if (target == LlvmTargetMachineArtifact.PC_BARE_METAL) {
			foreach (var exported in program.c_exports) {
				if (exported.external_symbol == "astra_trap_handler") {
					trap_handler = exported.target;
				}
			}
			if (trap_handler != null && (trap_handler.object_storage.length != 0 || trap_handler.heap_owners.length != 0 || trap_handler.buffer_storage.length != 0 || trap_handler.enum_slots.length != 0)) {
				reject ("PC trap handler cannot acquire storage ownership or implicit cleanup");
			}
			foreach (var function in program.functions) {
				foreach (var block in function.blocks) {
					foreach (var instruction in block.instructions) {
						var call = instruction as SsaCCallInstruction;
						if (call != null && call.target.metadata.device != null && call.target.metadata.device.operation == Astra.Foreign.PcDeviceOperation.BREAKPOINT && trap_handler == null) {
							reject ("PC breakpoint requires the exact source-defined astra_trap_handler export");
						}
						if (function == trap_handler && (instruction is SsaCallInstruction || instruction is SsaCCallInstruction)) {
							reject ("PC trap handler cannot call, allocate, nest a trap or acquire external effects");
						}
					}
				}
			}
		}
		local_classes.remove_all ();
		foreach (var owner in program.classes) {
			if (target != LlvmTargetMachineArtifact.PC_BARE_METAL || owner.polymorphic || owner.parent_class != null || owner.exception_root || ((ClassType) owner.semantic_type).is_interface || owner.generic_instance != null) {
				reject ("unqualified Class layout or lifecycle");
			}
			local_classes.insert (owner.semantic_type, true);
		}
		foreach (var owner in program.classes) {
			foreach (var field in owner.fields) {
				if (!value_type (field.semantic_type)) {
					reject ("Class field " + field.name);
				}
			}
		}
		foreach (var cleanup in program.cleanups) {
			if (!cleanup.is_object || cleanup.shared_type != null || cleanup.closure_type != null || cleanup.is_heap_object && (cleanup.object_class.allocation_policy == null || cleanup.object_class.allocation_policy.kind == Astra.Source.AllocationKind.HEAP)) {
				reject ("unqualified allocator or cleanup provider");
			}
		}
		foreach (var imported in program.c_functions) {
			if (target != LlvmTargetMachineArtifact.PC_BARE_METAL || imported.metadata.device == null || !imported.metadata.device.valid ()) {
				reject ("unqualified external provider");
			}
		}
		if (program.handles.length != 0 || program.enums.length != 0 || program.text_literals.length != 0) {
			reject ("classes, resources, providers, enums and text require hosted runtime");
		}
		foreach (var structure in program.structs) {
			foreach (var field in structure.fields) {
				if (!value_type (field.semantic_type)) {
					reject ("record field " + field.name);
				}
			}
		}
		foreach (var function in program.functions) {
			if (function.module_import_symbol != null || function.async_body != null || function.throws_type != null || function.buffer_storage.length != 0 || function.enum_slots.length != 0 || !value_type (function.return_type)) {
				reject ("function " + function.name);
			}
			foreach (var storage in function.object_storage) {
				if (storage.heap_allocated && (storage.object_class.allocation_policy == null || storage.object_class.allocation_policy.kind == Astra.Source.AllocationKind.HEAP)) {
					reject ("system heap is unavailable in the no-OS profile");
				}
			}
			foreach (var parameter in function.parameters) {
				if (!value_type (parameter.semantic_type)) {
					reject ("parameter " + parameter.name);
				}
			}
			foreach (var storage in function.storage) {
				if (!value_type (storage.semantic_type, true)) {
					reject ("storage " + storage.name);
				}
			}
			foreach (var block in function.blocks) {
				if (!(block.terminator is SsaBranch || block.terminator is SsaConditionalBranch || block.terminator is SsaReturn || block.terminator is SsaFunctionEnd)) {
					reject ("control-flow terminator");
				}
				foreach (var instruction in block.instructions) {
					var device_call = instruction as SsaCCallInstruction;
					if (device_call != null && target == LlvmTargetMachineArtifact.PC_BARE_METAL && device_call.target.metadata.device != null && device_call.target.metadata.device.valid ()) {
						continue;
					}
					if (instruction.result != null && !value_type (instruction.result.semantic_type)) {
						reject ("instruction value type " + instruction.result.semantic_type.display_name ());
					}
					if (!(instruction is SsaHeapOwnerEvent || instruction is SsaCleanupInstruction || instruction is SsaStorageReceiverInstruction || instruction is SsaObjectReferenceInstruction || instruction is SsaObjectValidateInstruction || instruction is SsaStructResultConsume || instruction is SsaVectorMemoryInstruction || instruction is SsaVectorDotInstruction || instruction is SsaSliceConstructInstruction || instruction is SsaSliceLengthInstruction || instruction is SsaSliceBoundsCheck || instruction is SsaCallInstruction || instruction is SsaPrefixInstruction || instruction is SsaBinaryInstruction || instruction is SsaIntegerShiftInstruction || instruction is SsaNumericGuard || instruction is SsaNumericConversionInstruction || instruction is SsaFloatConversionInstruction || instruction is SsaIntegerConversionInstruction || instruction is SsaDspInstruction || instruction is SsaVectorSplatInstruction || instruction is SsaVectorExtractInstruction || instruction is SsaVectorInsertInstruction || instruction is SsaVectorShuffleInstruction || instruction is SsaVectorSelectInstruction || instruction is SsaVectorConstructInstruction || instruction is SsaVectorReductionInstruction || instruction is SsaAddressOfInstruction || instruction is SsaInitializeInstruction || instruction is SsaStoreInstruction || instruction is SsaLoadInstruction || instruction is SsaValidatePlaceInstruction || instruction is SsaArrayInitialize || instruction is SsaArrayBoundsCheck)) {
						reject ("instruction outside the closed numeric/storage profile: " + instruction.get_type ().name ());
					}
				}
			}
		}
	}

	// Recheck the actual LLVM declarations, including compiler helpers. This
	// also runs after optimization: a pass cannot acquire a host provider.
	public static void verify_module(CApi.ModuleRef module, bool allocator = false) throws LlvmError {
		for (var function = CApi.first_function (module); (void*) function != null; function = CApi.next_function (function)) {
			if (CApi.count_basic_blocks (function) != 0) {
				continue;
			}
			size_t length;
			string name = CApi.value_name (function, out length);
			if (allocator && (name == "astra_alloc12_allocate" || name == "astra_alloc12_release")) {
				var context = CApi.module_context (module);
				var pointer = CApi.pointer_type_in_context (context, 0);
				var wide = CApi.int_type_in_context (context, 64);
				var word = CApi.int32_type_in_context (context);
				CApi.TypeRef[] parameters = name == "astra_alloc12_allocate" ? new CApi.TypeRef[] {
					pointer, wide, wide, word, wide
				} : new CApi.TypeRef[] {
					pointer, pointer, wide, wide
				};
				var signature = CApi.function_type (name == "astra_alloc12_allocate" ? pointer : word, parameters, parameters.length, 0);
				if ((void*) CApi.global_value_type (function) != (void*) signature || CApi.function_call_conv (function) != CApi.CallConv.C) {
					throw new LlvmError.VERIFICATION ("runtime none: allocation provider lost its sealed ABI");
				}
				continue;
			}
			bool permitted = allocator && name == "llvm.umul.with.overflow.i64" || name == "llvm.trap" || name.has_prefix ("llvm.memset.") || name.has_prefix ("llvm.memcpy.") || name.has_prefix ("llvm.memmove.") || name.has_prefix ("llvm.dbg.") || name.has_prefix ("llvm.lifetime.start.") || name.has_prefix ("llvm.lifetime.end.") || name.has_prefix ("llvm.sadd.sat.") || name.has_prefix ("llvm.uadd.sat.") || name.has_prefix ("llvm.ssub.sat.") || name.has_prefix ("llvm.usub.sat.");
			if (!permitted || CApi.intrinsic_id (function) == 0) {
				throw new LlvmError.VERIFICATION ("runtime none: external provider/helper '%s' is forbidden", name);
			}
		}
	}

}
}
