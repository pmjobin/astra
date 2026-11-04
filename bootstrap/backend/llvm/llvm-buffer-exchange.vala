// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception

using Astra.Source;
using Astra.Semantic;
using Astra.Ssa;

namespace Astra.Backend.LLVM {
// Copied identities and immutable type leaves only. No executable predecessor
// survives in this plan. Counts and allocation addresses are never type keys.
internal class LlvmBufferSlotPlan : Object {
	internal SliceType type;
	internal int cleanup;
	internal int storage;
	internal int owner;
	internal int class_ordinal;
	internal int field;
	internal int receiver;
	internal SemanticType? receiver_type;
	internal SemanticType? class_type;
	internal LlvmBufferSlotPlan (SliceType type, int cleanup, int storage, int owner, int class_ordinal, int field, int receiver, SemanticType? receiver_type, SemanticType? class_type) {
		this.type = type;
		this.cleanup = cleanup;
		this.storage = storage;
		this.owner = owner;
		this.class_ordinal = class_ordinal;
		this.field = field;
		this.receiver = receiver;
		this.receiver_type = receiver_type;
		this.class_type = class_type;
	}

	internal static LlvmBufferSlotPlan build(SsaBufferPlace place) throws LlvmError {
		if (!place.cleanup.is_buffer || (place.storage == null) == (place.field == null)) {
			throw new LlvmError.INVALID_INPUT ("exchange plan requires one complete buffer owner slot");
		}
		var pointer = place.field == null ? null : place.field.pointer as SsaDefinition;
		var plan = new LlvmBufferSlotPlan (place.cleanup.buffer_type, place.cleanup.ordinal, place.storage == null ? -1 : place.storage.ordinal, place.storage == null ? -1 : place.storage.owner_ordinal, place.field == null ? -1 : place.field.field.containing_type.ordinal, place.field == null ? -1 : place.field.field.ordinal, pointer == null ? -1 : pointer.ordinal, pointer == null ? null : pointer.semantic_type, place.field == null ? null : place.field.field.containing_type.semantic_type);
		plan.verify ();
		return plan;
	}

	internal void verify() throws LlvmError {
		bool local = storage >= 0;
		bool valid_field = class_ordinal >= 0 && field >= 0 && receiver >= 0 && class_type is ClassType && (receiver_type == class_type || (receiver_type is ReceiverType && ((ReceiverType) receiver_type).instance_type == class_type));
		if (cleanup < 0 || !BufferElementTypes.candidate (type.element_type) || (local ? owner < 0 || class_ordinal != -1 || field != -1 || receiver != -1 || receiver_type != null || class_type != null : storage != -1 || owner != -1 || !valid_field)) {
			throw new LlvmError.VERIFICATION ("exchange slot plan has invalid type, cleanup or storage identity");
		}
	}

	internal bool same(LlvmBufferSlotPlan other) {
		return type == other.type && cleanup == other.cleanup && storage == other.storage && owner == other.owner && class_ordinal == other.class_ordinal && field == other.field && receiver == other.receiver && receiver_type == other.receiver_type && class_type == other.class_type;
	}

	internal void validate(SsaFunction function, SsaBufferPlace place) throws LlvmError {
		verify ();
		if (!same (build (place))) {
			throw new LlvmError.INVALID_INPUT ("exchange slot plan does not correspond to its exact source operand");
		}
		if (place.storage != null) {
			if (storage >= function.buffer_storage.length || function.buffer_storage[storage] != place.storage || place.storage.cleanup != place.cleanup) {
				throw new LlvmError.INVALID_INPUT ("exchange slot is not a member of its function or cleanup contract");
			}
		} else {
			var declaration = place.field.field.containing_type;
			if (!(declaration is SsaClass) || field >= declaration.fields.length || declaration.fields[field] != place.field.field || place.field.semantic_type != type) {
				throw new LlvmError.INVALID_INPUT ("exchange field must match the exact class layout member");
			}
			bool found = place.field.pointer == function.implicit_receiver;
			foreach (var parameter in function.parameters) {
				if (place.field.pointer == parameter) {
					found = true;
				}
			}
			foreach (var block in function.blocks) {
				foreach (var parameter in block.parameters) {
					if (place.field.pointer == parameter) {
						found = true;
					}
				}
				foreach (var instruction in block.instructions) {
					if (place.field.pointer == instruction.result) {
						found = true;
					}
				}
			}
			if (!found) {
				throw new LlvmError.INVALID_INPUT ("exchange field receiver is outside its function");
			}
		}
	}

}

internal enum LlvmBufferExchangeStep {
	LEFT_BASE, LEFT_COUNT, RIGHT_BASE, RIGHT_COUNT, STORE_LEFT_BASE, STORE_LEFT_COUNT, STORE_RIGHT_BASE, STORE_RIGHT_COUNT
}

internal class LlvmBufferExchangePlan : Object {
	internal SourceSpan span;
	internal int function_ordinal;
	internal int block_ordinal;
	internal int position;
	internal LlvmBufferSlotPlan left;
	internal LlvmBufferSlotPlan right;
	private LlvmBufferExchangeStep[] steps;
	internal LlvmBufferExchangePlan (SourceSpan span, int function_ordinal, int block_ordinal, int position, LlvmBufferSlotPlan left, LlvmBufferSlotPlan right, LlvmBufferExchangeStep[]? steps = null) {
		this.span = span;
		this.function_ordinal = function_ordinal;
		this.block_ordinal = block_ordinal;
		this.position = position;
		this.left = left;
		this.right = right;
		this.steps = steps ?? new LlvmBufferExchangeStep[] {
			LlvmBufferExchangeStep.LEFT_BASE, LlvmBufferExchangeStep.LEFT_COUNT, LlvmBufferExchangeStep.RIGHT_BASE, LlvmBufferExchangeStep.RIGHT_COUNT, LlvmBufferExchangeStep.STORE_LEFT_BASE, LlvmBufferExchangeStep.STORE_LEFT_COUNT, LlvmBufferExchangeStep.STORE_RIGHT_BASE, LlvmBufferExchangeStep.STORE_RIGHT_COUNT
		};
	}

	internal static LlvmBufferExchangePlan build(SsaFunction function, SsaBlock block, int position) throws LlvmError {
		var operation = block.instructions[position] as SsaBufferExchangeInstruction;
		if (operation == null) {
			throw new LlvmError.INVALID_INPUT ("exchange plan requires its dedicated source operation");
		}
		var plan = new LlvmBufferExchangePlan (operation.span, function.ordinal, block.ordinal, position, LlvmBufferSlotPlan.build (operation.left), LlvmBufferSlotPlan.build (operation.right));
		plan.validate (function, operation);
		return plan;
	}

	internal void verify() throws LlvmError {
		left.verify ();
		right.verify ();
		if (function_ordinal < 0 || block_ordinal < 0 || position < 0 || left.type != right.type || left.cleanup != right.cleanup || steps.length != 8) {
			throw new LlvmError.VERIFICATION ("exchange plan requires two exact complete owner groups and one bounded permutation");
		}
		for (int i = 0; i < steps.length; i++) {
			if ((int) steps[i] != i) {
				throw new LlvmError.VERIFICATION ("exchange plan must capture both base/count groups before any store");
			}
		}
	}

	internal void validate(SsaFunction function, SsaBufferExchangeInstruction operation) throws LlvmError {
		verify ();
		if (function.ordinal != function_ordinal || block_ordinal >= function.blocks.length || position >= function.blocks[block_ordinal].instructions.length || function.blocks[block_ordinal].instructions[position] != operation || span.file != operation.span.file || span.start != operation.span.start || span.end != operation.span.end) {
			throw new LlvmError.INVALID_INPUT ("valid exchange plan belongs to a different source operation");
		}
		left.validate (function, operation.left);
		right.validate (function, operation.right);
		if (operation.left.cleanup != operation.right.cleanup) {
			throw new LlvmError.INVALID_INPUT ("exchange plan cannot merge distinct cleanup contracts");
		}
	}

}

// These associations are created when ordinary storage, receiver definitions
// and class layouts are bound, independently of exchange emission.
internal class LlvmBufferLocalBinding : Object {
	internal int function_ordinal;
	internal int storage;
	internal int owner;
	internal int cleanup;
	internal SliceType type;
	internal CApi.ValueRef address;
	internal LlvmBufferLocalBinding (int function_ordinal, SsaBufferStorage storage, CApi.ValueRef address) {
		this.function_ordinal = function_ordinal;
		this.storage = storage.ordinal;
		this.owner = storage.owner_ordinal;
		this.cleanup = storage.cleanup.ordinal;
		this.type = storage.cleanup.buffer_type;
		this.address = address;
	}

}
internal class LlvmBufferReceiverBinding : Object {
	internal int function_ordinal;
	internal int ordinal;
	internal SemanticType type;
	internal CApi.ValueRef value;
	internal CApi.ValueRef guard;
	internal LlvmBufferReceiverBinding (int function_ordinal, SsaDefinition source, CApi.ValueRef value) {
		this.function_ordinal = function_ordinal;
		this.ordinal = source.ordinal;
		this.type = source.semantic_type;
		this.value = value;
	}

}

// Physical dominance is checked from the retained LLVM graph, independently
// of the discarded SSA blocks and validation instruction identities.
internal class LlvmBufferExchangeOrder : Object {
	internal static bool dominates(CApi.BasicBlockRef origin, CApi.BasicBlockRef target) {
		var function = CApi.block_parent (target);
		if ((void*) function != (void*) CApi.block_parent (origin)) {
			return false;
		}
		var pending = new GenericArray<void*> ();
		var seen = new HashTable<void*, bool> (direct_hash, direct_equal);
		pending.add ((void*) CApi.entry_block (function));
		for (int i = 0; i < pending.length; i++) {
			var block = (CApi.BasicBlockRef) pending[i];
			if ((void*) block == (void*) origin || seen.contains ((void*) block)) {
				continue;
			}
			if ((void*) block == (void*) target) {
				return false;
			}
			seen.insert ((void*) block, true);
			var end = CApi.block_terminator (block);
			if ((void*) end == null) {
				continue;
			}
			for (uint j = 0; j < CApi.successor_count (end); j++) {
				pending.add ((void*) CApi.successor (end, j));
			}
		}
		return true;
	}

	internal static bool precedes(CApi.ValueRef left, CApi.ValueRef right) {
		if ((void*) CApi.is_instruction (left) == null || (void*) CApi.is_instruction (right) == null) {
			return false;
		}
		var a = CApi.instruction_parent (left);
		var b = CApi.instruction_parent (right);
		if ((void*) a != (void*) b) {
			return dominates (a, b);
		}
		for (var next = CApi.next_instruction (left); (void*) next != null; next = CApi.next_instruction (next)) {
			if ((void*) next == (void*) right) {
				return true;
			}
		}
		return false;
	}

	internal static void receiver(LlvmBufferReceiverBinding binding, CApi.ValueRef projection) throws LlvmError {
		if (!(binding.type is ClassType)) {
			return;
		}
		var guard = binding.guard;
		if ((void*) guard == null || (void*) CApi.is_instruction (guard) == null || CApi.opcode (guard) != CApi.Opcode.COND_BR || CApi.successor_count (guard) != 2) {
			throw new LlvmError.VERIFICATION ("exchange receiver requires its exact physical null guard");
		}
		var condition = CApi.condition (guard);
		if ((void*) CApi.is_instruction (condition) == null || CApi.opcode (condition) != CApi.Opcode.ICMP || CApi.predicate (condition) != CApi.IntPredicate.EQ || (void*) CApi.operand (condition, 0) != (void*) binding.value || (void*) CApi.is_constant_pointer_null (CApi.operand (condition, 1)) == null) {
			throw new LlvmError.VERIFICATION ("exchange receiver null check does not validate its exact reference");
		}
		var trap = CApi.successor (guard, 0);
		var continuation = CApi.successor (guard, 1);
		var end = CApi.block_terminator (trap);
		var call = CApi.first_instruction (trap);
		size_t length;
		if ((void*) end == null || CApi.opcode (end) != CApi.Opcode.UNREACHABLE || CApi.opcode (call) != CApi.Opcode.CALL || CApi.value_name (CApi.called_value (call), out length) != "llvm.trap" || (void*) CApi.next_instruction (call) != (void*) end || !dominates (continuation, CApi.instruction_parent (projection))) {
			throw new LlvmError.VERIFICATION ("exchange field projection requires its successful guard continuation and terminal trap");
		}
	}

}
internal class LlvmBufferFieldBinding : Object {
	internal int class_ordinal;
	internal SemanticType class_type;
	internal int ordinal;
	internal SemanticType type;
	internal CApi.TypeRef container;
	internal LlvmBufferFieldBinding (SsaStructField field, CApi.TypeRef container) {
		this.class_ordinal = field.containing_type.ordinal;
		this.class_type = field.containing_type.semantic_type;
		this.ordinal = field.ordinal;
		this.type = field.semantic_type;
		this.container = container;
	}

}

// Raw LLVM handles are borrowed from the artifact. They identify descriptor
// addresses, never payload addresses; no SSA Place or function is retained.
internal class LlvmBufferSlotBinding : Object {
	internal LlvmBufferSlotPlan plan;
	internal int function_ordinal;
	internal LlvmBufferLocalBinding? local_origin;
	internal LlvmBufferReceiverBinding? receiver_origin;
	internal LlvmBufferFieldBinding? field_origin;
	internal CApi.TypeRef carrier;
	internal CApi.TypeRef container;
	internal CApi.ValueRef receiver;
	internal CApi.ValueRef address;
	internal CApi.ValueRef base_address;
	internal CApi.ValueRef count_address;
	internal LlvmBufferSlotBinding (LlvmBufferSlotPlan plan, int function_ordinal, LlvmBufferLocalBinding? local_origin, LlvmBufferReceiverBinding? receiver_origin, LlvmBufferFieldBinding? field_origin, CApi.TypeRef carrier, CApi.TypeRef container, CApi.ValueRef receiver, CApi.ValueRef address, CApi.ValueRef base_address, CApi.ValueRef count_address) {
		this.plan = plan;
		this.carrier = carrier;
		this.container = container;
		this.receiver = receiver;
		this.address = address;
		this.base_address = base_address;
		this.count_address = count_address;
		this.function_ordinal = function_ordinal;
		this.local_origin = local_origin;
		this.receiver_origin = receiver_origin;
		this.field_origin = field_origin;
	}

	private static bool index(CApi.ValueRef value, uint expected) {
		return (void*) CApi.is_constant_int (value) != null && CApi.const_int_zext (value) == expected;
	}

	private static bool projection(CApi.ValueRef value, CApi.ValueRef root, CApi.TypeRef type, uint field) {
		return (void*) CApi.is_instruction (value) != null && CApi.opcode (value) == CApi.Opcode.GEP && CApi.operand_count (value) == 3 && (void*) CApi.operand (value, 0) == (void*) root && (void*) CApi.gep_source_type (value) == (void*) type && index (CApi.operand (value, 1), 0) && index (CApi.operand (value, 2), field);
	}

	internal void verify() throws LlvmError {
		plan.verify ();
		if (!projection (base_address, address, carrier, 0) || !projection (count_address, address, carrier, 1)) {
			throw new LlvmError.VERIFICATION ("exchange descriptor projections must select exact ordered base/count members");
		}
		if (plan.storage >= 0) {
			if (local_origin == null || receiver_origin != null || field_origin != null || local_origin.function_ordinal != function_ordinal || local_origin.storage != plan.storage || local_origin.owner != plan.owner || local_origin.cleanup != plan.cleanup || local_origin.type != plan.type || (void*) local_origin.address != (void*) address) {
				throw new LlvmError.VERIFICATION ("exchange local binding belongs to a different declared owner slot");
			}
			if ((void*) CApi.is_instruction (address) == null || CApi.opcode (address) != CApi.Opcode.ALLOCA || (void*) CApi.allocated_type (address) != (void*) carrier || (void*) receiver != null || (void*) container != null) {
				throw new LlvmError.VERIFICATION ("exchange local binding requires its complete descriptor storage");
			}
		} else {
			if (local_origin != null || receiver_origin == null || field_origin == null || receiver_origin.function_ordinal != function_ordinal || receiver_origin.ordinal != plan.receiver || receiver_origin.type != plan.receiver_type || (void*) receiver_origin.value != (void*) receiver || field_origin.class_ordinal != plan.class_ordinal || field_origin.class_type != plan.class_type || field_origin.ordinal != plan.field || field_origin.type != plan.type || (void*) field_origin.container != (void*) container) {
				throw new LlvmError.VERIFICATION ("exchange field binding belongs to a different receiver or class layout");
			}
			if (!projection (address, receiver, container, (uint) plan.field) || (void*) CApi.struct_type_at_index (container, (uint) plan.field) != (void*) carrier) {
				throw new LlvmError.VERIFICATION ("exchange field binding does not match its captured receiver and layout member");
			}
			LlvmBufferExchangeOrder.receiver (receiver_origin, address);
		}
	}

}

internal class LlvmBufferExchangeBinding : Object {
	internal LlvmBufferExchangePlan plan;
	internal LlvmBufferSlotBinding left;
	internal LlvmBufferSlotBinding right;
	internal CApi.ValueRef[] instructions;
	internal LlvmBufferExchangeBinding (LlvmBufferExchangePlan plan, LlvmBufferSlotBinding left, LlvmBufferSlotBinding right, CApi.ValueRef[] instructions) {
		this.plan = plan;
		this.left = left;
		this.right = right;
		this.instructions = instructions;
	}

	internal void verify() throws LlvmError {
		plan.verify ();
		left.verify ();
		right.verify ();
		if (left.function_ordinal != plan.function_ordinal || right.function_ordinal != plan.function_ordinal || !plan.left.same (left.plan) || !plan.right.same (right.plan) || (void*) left.carrier != (void*) right.carrier || instructions.length != 8) {
			throw new LlvmError.VERIFICATION ("exchange emission has mismatched source slots or an incomplete permutation");
		}
		var right_start = right.plan.storage >= 0 ? right.base_address : right.address;
		if (right.receiver_origin != null && right.receiver_origin.type is ClassType) {
			right_start = CApi.condition (right.receiver_origin.guard);
		}
		if (!LlvmBufferExchangeOrder.precedes (left.count_address, right_start) || !LlvmBufferExchangeOrder.precedes (right.count_address, instructions[0])) {
			throw new LlvmError.VERIFICATION ("exchange physical destinations and checks must precede snapshots in left-to-right order");
		}
		CApi.ValueRef[] addresses = {
			left.base_address, left.count_address, right.base_address, right.count_address
		};
		for (int i = 0; i < 8; i++) {
			var instruction = instructions[i];
			bool load = i < 4;
			if ((void*) CApi.is_instruction (instruction) == null || CApi.opcode (instruction) != (load ? CApi.Opcode.LOAD : CApi.Opcode.STORE) || CApi.operand_count (instruction) != (load ? 1 : 2) || CApi.get_volatile (instruction) != 0 || CApi.get_ordering (instruction) != 0) {
				throw new LlvmError.VERIFICATION ("exchange region requires only four ordinary loads then four ordinary stores");
			}
			if (i > 0 && (void*) CApi.next_instruction (instructions[i - 1]) != (void*) instruction) {
				throw new LlvmError.VERIFICATION ("exchange capture/commit region contains an intervening effect or missing component");
			}
			if ((void*) CApi.operand (instruction, load ? 0 : 1) != (void*) addresses[i % 4]) {
				throw new LlvmError.VERIFICATION ("exchange accesses a different descriptor slot or component");
			}
			if (load) {
				if ((void*) CApi.type_of (instruction) != (void*) CApi.struct_type_at_index (left.carrier, (uint) (i % 2))) {
					throw new LlvmError.VERIFICATION ("exchange captured component has the wrong physical type");
				}
			} else if ((void*) CApi.operand (instruction, 0) != (void*) instructions[(i - 4 + 2) % 4]) {
				throw new LlvmError.VERIFICATION ("exchange store does not use the opposite complete pre-store snapshot");
			}
		}
		for (int i = 0; i < 4; i++) {
			int uses = 0;
			for (var use = CApi.first_use (instructions[i]); (void*) use != null; use = CApi.next_use (use)) {
				if ((void*) CApi.user (use) != (void*) instructions[4 + (i + 2) % 4]) {
					throw new LlvmError.VERIFICATION ("exchange snapshot escapes its unique opposite-slot store");
				}
				uses++;
			}
			if (uses != 1) {
				throw new LlvmError.VERIFICATION ("exchange snapshot must supply exactly one opposite-slot store");
			}
		}
	}

}
}
