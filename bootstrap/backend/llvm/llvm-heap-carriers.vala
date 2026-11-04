// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
namespace Astra.Backend.LLVM {
// Descriptor imports retain nominal parent/destructor roles and exact
// external declarations; their producer initializer remains opaque.
internal class LlvmScopedDescriptorAuthority : Object {
	internal CApi.ValueRef value;
	internal CApi.ValueRef parent;
	internal CApi.ValueRef destroy;
	internal bool imported;
	private LlvmClassGlobalBinding global;
	private LlvmNativeModuleBinding? cleanup;
	internal LlvmScopedDescriptorAuthority (CApi.ValueRef value, CApi.ValueRef parent, CApi.ValueRef destroy, LlvmClassGlobalBinding global, bool imported) {
		this.value = value;
		this.parent = parent;
		this.destroy = destroy;
		this.global = global;
		this.imported = imported;
		if (imported && (void*) CApi.is_function (destroy) != null) {
			size_t length;
			cleanup = new LlvmNativeModuleBinding (destroy, CApi.global_value_type (destroy), CApi.value_name (destroy, out length), true);
		}
	}

	internal void verify() throws LlvmError {
		global.verify ();
		if (imported) {
			if (cleanup == null) {
				throw new LlvmError.VERIFICATION ("opaque scoped descriptor lacks its native destructor role");
			}
			cleanup.verify ();
		}
	}

}
// Exact native descriptor identity is copied after descriptors are emitted.
// The owning field graph and the dispatch header have separate proof duties.
internal class LlvmScopedExceptionShape : Object {
	internal CApi.TypeRef layout;
	internal CApi.TypeRef header;
	private CApi.ValueRef descriptor;
	private LlvmScopedDescriptorAuthority authority;
	private CApi.ValueRef initializer;
	private CApi.TypeRef descriptor_layout;
	private CApi.ValueRef destructor;
	internal CApi.ValueRef destructor_target() {
		return destructor;
	}

	internal LlvmScopedExceptionShape (CApi.TypeRef layout, LlvmScopedDescriptorAuthority? authority) throws LlvmError {
		if (authority == null) {
			throw new LlvmError.LOWERING ("scoped exception requires its exact immutable native descriptor");
		}
		authority.verify ();
		this.authority = authority;
		var descriptor = authority.value;
		this.layout = layout;
		this.descriptor = descriptor;
		initializer = CApi.get_initializer (descriptor);
		var pointer = CApi.pointer_type_in_context (CApi.type_context (layout), 0);
		CApi.TypeRef[] fields = {
			pointer, pointer
		};
		header = CApi.struct_type_in_context (CApi.type_context (layout), fields, 2, 0);
		CApi.TypeRef[] entries = {
			pointer, pointer, pointer
		};
		descriptor_layout = CApi.struct_type_in_context (CApi.type_context (layout), entries, 3, 0);
		if ((void*) CApi.global_value_type (descriptor) != (void*) descriptor_layout || !authority.imported && ((void*) initializer == null || CApi.operand_count (initializer) != 3 || (void*) CApi.is_function (CApi.operand (initializer, 1)) == null)) {
			throw new LlvmError.LOWERING ("scoped exception requires its exact native destructor descriptor");
		}
		destructor = authority.imported ? authority.destroy : CApi.operand (initializer, 1);
	}

	internal int member(CApi.ValueRef address, CApi.ValueRef root) {
		if ((void*) CApi.is_instruction (address) == null || CApi.opcode (address) != CApi.Opcode.GEP || CApi.operand_count (address) != 3 || (void*) CApi.operand (address, 0) != (void*) root || (void*) CApi.gep_source_type (address) != (void*) header && (void*) CApi.gep_source_type (address) != (void*) layout || (void*) CApi.is_constant_int (CApi.operand (address, 1)) == null || CApi.const_int_zext (CApi.operand (address, 1)) != 0 || (void*) CApi.is_constant_int (CApi.operand (address, 2)) == null) {
			return -1;
		}
		uint64 field = CApi.const_int_zext (CApi.operand (address, 2));
		return field < 2 ? (int) field : -1;
	}

	internal void verify(CApi.ValueRef root, CApi.ValueRef publication) throws LlvmError {
		var roots = new GenericArray<void*> ();
		roots.add ((void*) root);
		verify_roots (roots, publication);
	}

	internal void verify_roots(GenericArray<void*> roots, CApi.ValueRef publication) throws LlvmError {
		verify_descriptor ();
		CApi.ValueRef initialized = (CApi.ValueRef) null;
		foreach (void* item in roots) {
			var root = (CApi.ValueRef) item;
			for (var use = CApi.first_use (root); (void*) use != null; use = CApi.next_use (use)) {
				var address = CApi.user (use);
				if (member (address, root) != 0) {
					continue;
				}
				for (var access = CApi.first_use (address); (void*) access != null; access = CApi.next_use (access)) {
					var store = CApi.user (access);
					if ((void*) CApi.is_instruction (store) == null || CApi.opcode (store) != CApi.Opcode.STORE) {
						continue;
					}
					if ((void*) CApi.operand (store, 1) != (void*) address || (void*) CApi.operand (store, 0) != (void*) descriptor || (void*) initialized != null || CApi.get_volatile (store) != 0 || CApi.get_ordering (store) != 0) {
						throw new LlvmError.VERIFICATION ("scoped exception lost its exact descriptor initialization");
					}
					initialized = store;
				}
			}
		}
		if ((void*) initialized == null || !LlvmBufferExchangeOrder.precedes (initialized, publication)) {
			size_t length;
			throw new LlvmError.VERIFICATION ("scoped exception descriptor must be initialized before publication (function=%s, publication=%s, opcode=%d, initialized=%d)", CApi.value_name (CApi.block_parent (CApi.instruction_parent (publication)), out length), CApi.value_name (publication, out length), (int) CApi.opcode (publication), (void*) initialized == null ? 0 : 1);
		}
	}

	internal void verify_descriptor() throws LlvmError {
		if (CApi.is_global_constant (descriptor) != 1 || (void*) CApi.get_initializer (descriptor) != (void*) initializer) {
			throw new LlvmError.VERIFICATION ("scoped exception lost its immutable native descriptor");
		}
		authority.verify ();
	}

	internal void verify_empty_parent(LlvmScopedExceptionShape parent) throws LlvmError {
		verify_descriptor ();
		parent.verify_descriptor ();
		if (same (parent)) {
			return;
		}
		if (CApi.type_kind (layout) != CApi.TypeKind.STRUCT || CApi.is_packed_struct (layout) != 0 || CApi.count_struct_element_types (layout) != 1 || (void*) CApi.struct_type_at_index (layout, 0) != (void*) parent.layout || (void*) (authority.imported ? authority.parent : CApi.operand (initializer, 0)) != (void*) parent.descriptor) {
			throw new LlvmError.VERIFICATION ("empty inherited error lost its exact zero-offset base layout and descriptor");
		}
	}

	internal bool same(LlvmScopedExceptionShape other) {
		return (void*) layout == (void*) other.layout && (void*) descriptor == (void*) other.descriptor;
	}

	private static bool ordinary_pointer_load(CApi.ValueRef value) {
		return (void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.LOAD && CApi.type_kind (CApi.type_of (value)) == CApi.TypeKind.POINTER && CApi.get_volatile (value) == 0 && CApi.get_ordering (value) == 0;
	}

	internal bool destructor_value(CApi.ValueRef value, CApi.ValueRef root) {
		if (!ordinary_pointer_load (value)) {
			return false;
		}
		var address = CApi.operand (value, 0);
		if ((void*) CApi.is_instruction (address) == null || CApi.opcode (address) != CApi.Opcode.GEP || (void*) CApi.gep_source_type (address) != (void*) descriptor_layout || CApi.operand_count (address) != 3 || (void*) CApi.is_constant_int (CApi.operand (address, 1)) == null || CApi.const_int_zext (CApi.operand (address, 1)) != 0 || (void*) CApi.is_constant_int (CApi.operand (address, 2)) == null || CApi.const_int_zext (CApi.operand (address, 2)) != 1) {
			return false;
		}
		var owner = CApi.operand (address, 0);
		return ordinary_pointer_load (owner) && member (CApi.operand (owner, 0), root) == 0;
	}

	internal bool destructor_call(CApi.ValueRef call, CApi.ValueRef root) throws LlvmError {
		if (!destructor_value (CApi.called_value (call), root)) {
			return false;
		}
		verify_descriptor ();
		if (CApi.argument_count (call) != 1 || (void*) CApi.operand (call, 0) != (void*) root || (void*) CApi.called_function_type (call) != (void*) CApi.global_value_type (destructor) || CApi.instruction_call_conv (call) != LlvmLowering.CALL_CONVENTION) {
			throw new LlvmError.VERIFICATION ("scoped exception lost its exact dynamic destructor ABI");
		}
		return true;
	}

	internal void verify_inherited(CApi.ValueRef root) throws LlvmError {
		verify_descriptor ();
		for (var use = CApi.first_use (root); (void*) use != null; use = CApi.next_use (use)) {
			var address = CApi.user (use);
			if (member (address, root) != 0) {
				continue;
			}
			for (var access = CApi.first_use (address); (void*) access != null; access = CApi.next_use (access)) {
				var user = CApi.user (access);
				if ((void*) CApi.is_instruction (user) != null && CApi.opcode (user) == CApi.Opcode.STORE) {
					throw new LlvmError.VERIFICATION ("scoped exception caller cannot overwrite its inherited descriptor");
				}
			}
		}
	}

}
// Reconstruct Class backing from actual IR and the independently
// copied native field layout. No predecessor graph or allocation marker survives.
internal class LlvmScopedHeapCarrier : Object {
	internal CApi.ValueRef root;
	internal CApi.ValueRef allocation;
	internal CApi.TypeRef layout;
	internal LlvmScopedExceptionShape? exception_shape;
	internal LlvmScopedExceptionShape? empty_base_shape;
	internal LlvmScopedOwnedInputs? empty_contract;
	internal bool returned_error { get; private set; }
	internal bool observed_error;
	internal bool alias_nullable;
	internal bool nullable { get; private set; }
	private bool contextual;
	private CApi.ValueRef tag;
	internal static LlvmScopedHeapCarrier from_error_call(CApi.ValueRef call, LlvmScopedOwnedInputs contract) {
		var result = new LlvmScopedHeapCarrier ();
		result.root = call;
		result.allocation = call;
		result.layout = contract.error_layout;
		result.exception_shape = contract.error_shape;
		result.nullable = true;
		result.returned_error = true;
		return result;
	}

	private static bool number(CApi.ValueRef value, uint64 expected) {
		return (void*) CApi.is_constant_int (value) != null && CApi.const_int_zext (value) == expected;
	}

	internal static bool named_call(CApi.ValueRef value, string name) {
		if ((void*) CApi.is_instruction (value) == null || CApi.opcode (value) != CApi.Opcode.CALL || (void*) CApi.is_function (CApi.called_value (value)) == null) {
			return false;
		}
		size_t length;
		return CApi.value_name (CApi.called_value (value), out length) == name;
	}

	internal static bool free_call(CApi.ValueRef call) throws LlvmError {
		if (!named_call (call, "free")) {
			return false;
		}
		var context = CApi.type_context (CApi.type_of (call));
		CApi.TypeRef[] inputs = {
			CApi.pointer_type_in_context (context, 0)
		};
		var type = CApi.function_type (CApi.void_type_in_context (context), inputs, 1, 0);
		var target = CApi.called_value (call);
		if (CApi.argument_count (call) != 1 || (void*) CApi.global_value_type (target) != (void*) type || (void*) CApi.called_function_type (call) != (void*) type || CApi.count_basic_blocks (target) != 0 || CApi.function_call_conv (target) != CApi.CallConv.C || CApi.instruction_call_conv (call) != CApi.CallConv.C) {
			throw new LlvmError.VERIFICATION ("heap carrier lost its exact external free ABI");
		}
		return true;
	}

	internal bool release_call(CApi.ValueRef call) throws LlvmError {
		if (!contextual) {
			return free_call (call);
		}
		if (!named_call (call, "astra_context17_release_origin_checked")) {
			return false;
		}
		var context = CApi.type_context (layout);
		CApi.TypeRef[] inputs = {
			CApi.pointer_type_in_context (context, 0), CApi.int_type_in_context (context, 64)
		};
		var type = CApi.function_type (CApi.int32_type_in_context (context), inputs, 2, 0);
		var target = CApi.called_value (call);
		if (CApi.argument_count (call) != 2 || (void*) CApi.global_value_type (target) != (void*) type || (void*) CApi.called_function_type (call) != (void*) type || CApi.count_basic_blocks (target) != 0 || CApi.function_call_conv (target) != CApi.CallConv.C || CApi.instruction_call_conv (call) != CApi.CallConv.C || (void*) CApi.operand (call, 1) != (void*) tag) {
			throw new LlvmError.VERIFICATION ("heap carrier lost its exact context retirement ABI or allocation tag");
		}
		return true;
	}

	private static bool sole_predecessor(CApi.ValueRef function, CApi.BasicBlockRef target, CApi.BasicBlockRef expected) {
		uint count = 0;
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			var end = CApi.block_terminator (block);
			for (uint s = 0; s < CApi.successor_count (end); s++) {
				if ((void*) CApi.successor (end, s) == (void*) target) {
					if ((void*) block != (void*) expected) {
						return false;
					}
					count++;
				}
			}
		}
		return count == 1;
	}

	internal static LlvmScopedHeapCarrier? recognize(CApi.ValueRef root, LlvmScopedFieldContract fields) throws LlvmError {
		var layout = fields.layout;
		bool contextual = !fields.default_backing;
		if (contextual && fields.backing_mode < 0) {
			throw new LlvmError.VERIFICATION ("scoped field carrier cannot bypass its prescribed allocator backing");
		}
		if ((void*) CApi.is_instruction (root) == null || CApi.opcode (root) != CApi.Opcode.PHI) {
			return null;
		}
		if (CApi.incoming_count (root) != 2) {
			throw new LlvmError.VERIFICATION ("heap carrier requires its exact backing alternatives");
		}
		uint empty = (void*) CApi.is_constant_pointer_null (CApi.incoming_value (root, 0)) != null ? 0 : 1;
		uint live = 1 - empty;
		var allocation = CApi.incoming_value (root, live);
		var joined = CApi.instruction_parent (root);
		var function = CApi.block_parent (joined);
		var absent = CApi.block_terminator (CApi.incoming_block (root, empty));
		if ((void*) CApi.is_constant_pointer_null (CApi.incoming_value (root, empty)) == null || !named_call (allocation, contextual ? "astra_context17_allocate_mode" : "calloc") || CApi.opcode (absent) != CApi.Opcode.COND_BR || CApi.successor_count (absent) != 2 || !number (CApi.operand (absent, 0), 0) || (void*) CApi.successor (absent, 0) != (void*) joined) {
			throw new LlvmError.VERIFICATION ("heap carrier lost its prescribed allocation and unreachable empty edge");
		}
		var context = CApi.type_context (layout);
		var size = CApi.int_type_in_context (context, 64);
		var word = CApi.int32_type_in_context (context);
		var pointer = CApi.pointer_type_in_context (context, 0);
		CApi.TypeRef[] inputs = contextual ? new CApi.TypeRef[] {
			pointer, size, size, word, size, word
		} : new CApi.TypeRef[] {
			size, size
		};
		var type = CApi.function_type (pointer, inputs, inputs.length, 0);
		var target = CApi.called_value (allocation);
		uint count = contextual ? 1 : 0;
		var extent = fields.scoped_receiver ? fields.backing_size : CApi.size_of (layout);
		if (CApi.argument_count (allocation) != inputs.length || !number (CApi.operand (allocation, count), 1) || (void*) CApi.operand (allocation, count + 1) != (void*) extent || (void*) CApi.global_value_type (target) != (void*) type || (void*) CApi.called_function_type (allocation) != (void*) type || CApi.count_basic_blocks (target) != 0 || CApi.function_call_conv (target) != CApi.CallConv.C || CApi.instruction_call_conv (allocation) != CApi.CallConv.C) {
			throw new LlvmError.VERIFICATION ("heap carrier lost its exact Class extent or external allocator ABI");
		}
		if (contextual && (!number (CApi.operand (allocation, 3), fields.backing_alignment) || (void*) CApi.operand (allocation, 4) != (void*) fields.backing_tag || !number (CApi.operand (allocation, 5), fields.backing_mode))) {
			throw new LlvmError.VERIFICATION ("heap carrier lost its prescribed context mode, alignment or allocation tag");
		}
		var successful = CApi.incoming_block (root, live);
		var success_end = CApi.block_terminator (successful);
		CApi.ValueRef comparison = (CApi.ValueRef) null;
		if (CApi.opcode (success_end) != CApi.Opcode.UNCOND_BR || CApi.successor_count (success_end) != 1 || (void*) CApi.successor (success_end, 0) != (void*) joined) {
			throw new LlvmError.VERIFICATION ("heap carrier lost its backing publication edge");
		}
		for (var block = CApi.first_block (function); (void*) block != null; block = CApi.next_block (block)) {
			var end = CApi.block_terminator (block);
			if (CApi.opcode (end) != CApi.Opcode.COND_BR || CApi.successor_count (end) != 2 || (void*) CApi.successor (end, 1) != (void*) successful) {
				continue;
			}
			var condition = CApi.operand (end, 0);
			if ((void*) CApi.is_instruction (condition) == null || CApi.opcode (condition) != CApi.Opcode.ICMP || CApi.predicate (condition) != CApi.IntPredicate.EQ || (void*) CApi.operand (condition, 0) != (void*) allocation || (void*) CApi.is_constant_pointer_null (CApi.operand (condition, 1)) == null) {
				continue;
			}
			var trap = CApi.successor (end, 0);
			var call = CApi.first_instruction (trap);
			var trap_end = CApi.block_terminator (trap);
			if ((void*) call == null || (void*) trap_end == null || !named_call (call, "llvm.trap") || CApi.intrinsic_id (CApi.called_value (call)) != CApi.lookup_intrinsic_id ("llvm.trap", 9) || CApi.opcode (trap_end) != CApi.Opcode.UNREACHABLE || (void*) CApi.next_instruction (call) != (void*) trap_end || !sole_predecessor (function, successful, block) || !LlvmBufferExchangeOrder.precedes (allocation, end)) {
				continue;
			}
			comparison = condition;
		}
		for (var use = CApi.first_use (allocation); (void*) use != null; use = CApi.next_use (use)) {
			var user = CApi.user (use);
			bool compared = (void*) CApi.is_instruction (user) != null && CApi.opcode (user) == CApi.Opcode.ICMP && (CApi.predicate (user) == CApi.IntPredicate.EQ || CApi.predicate (user) == CApi.IntPredicate.NE) && ((void*) CApi.is_constant_pointer_null (CApi.operand (user, 0)) != null || (void*) CApi.is_constant_pointer_null (CApi.operand (user, 1)) != null);
			if ((void*) user != (void*) root && !compared) {
				throw new LlvmError.VERIFICATION ("heap carrier raw allocation escaped its original backing channel");
			}
		}
		var result = new LlvmScopedHeapCarrier ();
		result.root = root;
		result.allocation = allocation;
		result.layout = layout;
		result.contextual = contextual;
		result.tag = fields.backing_tag;
		result.nullable = (void*) comparison == null;
		result.exception_shape = fields.exception_shape;
		result.empty_base_shape = fields.empty_base_shape;
		return result;
	}

}
}
